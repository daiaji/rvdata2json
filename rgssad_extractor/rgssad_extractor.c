#include "ruby.h"
#include <errno.h>   // For errno constants like EEXIST, ENOMEM, EILSEQ
#include <stdbool.h> // For bool type
#include <stdio.h> // For FILE, fopen, fclose, fseek, ftell, fread, fwrite, printf, EOF
#include <stdlib.h> // For malloc, realloc, free
#include <string.h> // For memcpy, memcmp, strerror

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <wchar.h> // Required for _wfopen
#include <windows.h>
#else                  // Assuming Linux/macOS or other POSIX-like systems
#include <sys/stat.h>  // For mkdir mode
#include <sys/types.h> // For mkdir mode
#endif

// --- Platform specific path handling (Global buffer reused) ---
#ifdef _WIN32
wchar_t *wchar_buffer = NULL;
size_t wchar_buffer_size = 0;

int utf8_to_wchar(const char *utf8_str, size_t len) {
  int required_size_int =
      MultiByteToWideChar(CP_UTF8, 0, utf8_str, (int)len, NULL, 0);
  if (required_size_int <= 0 && len > 0) {
    errno = EILSEQ;
    return -1;
  }
  size_t required_size = (size_t)required_size_int + 1;

  if (required_size > wchar_buffer_size) {
    wchar_t *new_buffer =
        (wchar_t *)realloc(wchar_buffer, sizeof(wchar_t) * required_size);
    if (!new_buffer) {
      errno = ENOMEM;
      return -1;
    }
    wchar_buffer = new_buffer;
    wchar_buffer_size = required_size;
  }

  int chars_converted = MultiByteToWideChar(CP_UTF8, 0, utf8_str, (int)len,
                                            wchar_buffer, (int)required_size);
  if (chars_converted <= 0 && len > 0) {
    errno = EILSEQ;
    return -1;
  }
  wchar_buffer[chars_converted] = L'\0';
  return 0;
}

#else // Linux/macOS etc. - Use UTF-8 directly
char *char_buffer = NULL;
size_t char_buffer_size = 0;

int utf8_to_mb(const char *utf8_str, size_t len) {
  size_t required_size = len + 1;
  if (required_size > char_buffer_size) {
    char *new_buffer =
        (char *)realloc(char_buffer, sizeof(char) * required_size);
    if (!new_buffer) {
      errno = ENOMEM;
      return -1;
    }
    char_buffer = new_buffer;
    char_buffer_size = required_size;
  }
  memcpy(char_buffer, utf8_str, len);
  char_buffer[len] = '\0';
  return 0;
}
#endif

// --- Ruby Integration Variables ---
VALUE RgssadExtractor_module = Qnil; // Changed from R3EXS
ID rgssad_extractor_RGSSADFileError_id;
ID rgssad_extractor_File_id;
ID rgssad_extractor_FileUtils_id;
ID rgssad_extractor_join_id;
ID rgssad_extractor_dirname_id;
ID rgssad_extractor_mkdir_p_id;
VALUE rgssad_extractor_RGSSADFileError_class;
VALUE rgssad_extractor_File_module;
VALUE rgssad_extractor_FileUtils_module;

// Helper to raise rb_sys_fail with a custom message + path + errno string
static void sys_fail_helper(const char *msg, const char *path) {
  char full_msg[1024];
  snprintf(full_msg, sizeof(full_msg), "%s: %s", msg, path);
  rb_sys_fail(full_msg);
}

// --- Platform specific file opening ---
FILE *platform_fopen(const char *utf8_path, const char *mode) {
#ifdef _WIN32
  wchar_t w_mode[10] = {0};
  size_t i;
  for (i = 0; mode[i] != '\0' && i < sizeof(w_mode) / sizeof(wchar_t) - 1;
       ++i) {
    w_mode[i] = (wchar_t)mode[i];
  }
  w_mode[i] = L'\0';

  if (utf8_to_wchar(utf8_path, strlen(utf8_path)) == -1) {
    return NULL;
  }
  return _wfopen(wchar_buffer, w_mode);
#else
  return fopen(utf8_path, mode);
#endif
}

// --- Decryption Logic (Unchanged) ---
#define MOD_4_MASK 0b11
#define MASK_KEY_1 0x000000FF
#define MASK_KEY_2 0x0000FFFF
#define MASK_KEY_3 0x00FFFFFF

enum RGSSAD_TYPE { UNKNOWN, RGSSADv1, RGSSADv3, Fux2Pack2 };
#define RGSSADv1_INITIAL_KEY 0xDEADCAFE
#define HEADER_SIZE 8
#define V3_SEED_SIZE 4

unsigned int decrypt_integer_v1(unsigned int encrypted_val, unsigned int *key) {
  unsigned int decrypted_val = encrypted_val ^ (*key);
  *key = (*key) * 7 + 3;
  return decrypted_val;
}

void decrypt_filename_v1(unsigned char *data, size_t n, unsigned int *key) {
  for (size_t i = 0; i < n; ++i) {
    data[i] ^= ((*key) & 0xFF);
    *key = (*key) * 7 + 3;
  }
}

unsigned int decrypt_integer_v3(unsigned int encrypted_val, unsigned int key) {
  return encrypted_val ^ key;
}

void decrypt_filename_v3(unsigned char *data, size_t n, unsigned int key) {
  size_t q = n >> 2;
  char r = n & MOD_4_MASK;
  unsigned int *data_p = (unsigned int *)data;
  for (size_t i = 0; i < q; ++i) {
    data_p[i] ^= key;
  }
  unsigned char *remainder_p = (unsigned char *)(data_p + q);
  if (r >= 1) remainder_p[0] ^= (key & MASK_KEY_1);
  if (r >= 2) remainder_p[1] ^= ((key >> 8) & MASK_KEY_1);
  if (r >= 3) remainder_p[2] ^= ((key >> 16) & MASK_KEY_1);
}

void decrypt_file_data(unsigned char *data, size_t n, unsigned int key) {
  size_t q = n >> 2;
  char r = n & MOD_4_MASK;
  unsigned int *data_p = (unsigned int *)data;
  for (size_t i = 0; i < q; ++i) {
    data_p[i] ^= key;
    key = key * 7 + 3;
  }
  unsigned char *remainder_p = (unsigned char *)(data_p + q);
  if (r == 1) *remainder_p ^= (key & MASK_KEY_1);
  else if (r == 2) *(unsigned short *)remainder_p ^= (key & MASK_KEY_2);
  else if (r == 3) {
    unsigned char *key_bytes = (unsigned char *)&key;
    remainder_p[0] ^= key_bytes[0];
    remainder_p[1] ^= key_bytes[1];
    remainder_p[2] ^= key_bytes[2];
  }
}

/* Main Extraction Function (Renamed) */
VALUE rgssad_extractor_extract_archive(VALUE _self, VALUE target_path_rb,
                                      VALUE output_dir_rb, VALUE verbose_rb) { // Renamed function
  bool verbose = RTEST(verbose_rb);
  char *target_path_c = StringValueCStr(target_path_rb);

  FILE *input_file = NULL;
  FILE *output_file = NULL;
  unsigned char *entry_data_buffer = NULL;
  unsigned char *encrypted_filename_buffer = NULL;
  char *decrypted_filename_c = NULL;

  enum RGSSAD_TYPE archive_type = UNKNOWN;
  unsigned int metadata_key_v3 = 0;
  unsigned int current_key_v1 = RGSSADv1_INITIAL_KEY;

  input_file = platform_fopen(target_path_c, "rb");
  if (!input_file) {
    sys_fail_helper("Failed to open input file", target_path_c);
    goto cleanup;
  }

  unsigned char header[HEADER_SIZE];
  size_t bytes_read = fread(header, 1, HEADER_SIZE, input_file);
  if (bytes_read < HEADER_SIZE) {
    if (ferror(input_file)) {
      sys_fail_helper("Failed to read header", target_path_c);
    } else {
      rb_raise(rgssad_extractor_RGSSADFileError_class, // Use new class variable
               "File is too small or truncated (header): %s", target_path_c);
    }
    goto cleanup;
  }

  if (memcmp(header, "RGSSAD\x00\x01", HEADER_SIZE) == 0) {
    archive_type = RGSSADv1;
  } else if (memcmp(header, "RGSSAD\x00\x03", HEADER_SIZE) == 0) {
    archive_type = RGSSADv3;
    unsigned int seed;
    bytes_read = fread(&seed, 1, V3_SEED_SIZE, input_file);
    if (bytes_read < V3_SEED_SIZE) {
      rb_raise(rgssad_extractor_RGSSADFileError_class, // Use new class variable
               "Truncated after v3 header (seed missing): %s", target_path_c);
      goto cleanup;
    }
    metadata_key_v3 = seed * 9 + 3;
  } else if (memcmp(header, "Fux2Pack", HEADER_SIZE) == 0) {
    archive_type = Fux2Pack2;
    bytes_read = fread(&metadata_key_v3, 1, V3_SEED_SIZE, input_file);
    if (bytes_read < V3_SEED_SIZE) {
      rb_raise(rgssad_extractor_RGSSADFileError_class, // Use new class variable
               "Truncated after Fux2 header (key missing): %s", target_path_c);
      goto cleanup;
    }
  } else {
    rb_raise(rgssad_extractor_RGSSADFileError_class, // Use new class variable
             "Unknown or invalid archive header: %s", target_path_c);
    goto cleanup;
  }

  if (verbose) {
#ifdef _WIN32
    if (utf8_to_wchar(target_path_c, strlen(target_path_c)) == -1) {}
    printf("\e[2K\e[32mProcessing \e[0m%ls\n", wchar_buffer);
#else
    if (utf8_to_mb(target_path_c, strlen(target_path_c)) == -1) {}
    printf("\e[2K\e[32mProcessing \e[0m%s\n", char_buffer);
#endif
  }

  while (1) {
    unsigned int file_offset = 0;
    unsigned int entry_file_size = 0;
    unsigned int file_data_key = 0;
    unsigned int filename_size = 0;
    long metadata_read_pos = -1;

    free(encrypted_filename_buffer); encrypted_filename_buffer = NULL;
    free(decrypted_filename_c); decrypted_filename_c = NULL;
    free(entry_data_buffer); entry_data_buffer = NULL;

    if (archive_type == RGSSADv1) {
      unsigned int encrypted_val;
      bytes_read = fread(&encrypted_val, 1, sizeof(unsigned int), input_file);
      if (bytes_read < sizeof(unsigned int)) {
        if (feof(input_file) && bytes_read == 0) break;
        if (ferror(input_file)) sys_fail_helper("Error reading v1 filename size", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated before v1 filename size: %s", target_path_c);
        goto cleanup;
      }
      filename_size = decrypt_integer_v1(encrypted_val, &current_key_v1);
      if (filename_size == 0 || filename_size > 1024 * 1024) {
        rb_raise(rgssad_extractor_RGSSADFileError_class, "Invalid v1 filename size (%u): %s", filename_size, target_path_c);
        goto cleanup;
      }
      encrypted_filename_buffer = (unsigned char *)malloc(filename_size);
      if (!encrypted_filename_buffer) { sys_fail_helper("Failed to allocate buffer for v1 filename", target_path_c); goto cleanup; }
      bytes_read = fread(encrypted_filename_buffer, 1, filename_size, input_file);
      if (bytes_read < filename_size) {
        if (ferror(input_file)) sys_fail_helper("Error reading v1 filename data", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated during v1 filename read: %s", target_path_c);
        goto cleanup;
      }
      if (verbose) printf("\e[34mDecrypting DataName...\r");
      decrypt_filename_v1(encrypted_filename_buffer, filename_size, &current_key_v1);
      decrypted_filename_c = (char *)malloc(filename_size + 1);
      if (!decrypted_filename_c) { sys_fail_helper("Failed to allocate buffer for decrypted v1 filename", target_path_c); goto cleanup; }
      memcpy(decrypted_filename_c, encrypted_filename_buffer, filename_size);
      decrypted_filename_c[filename_size] = '\0';
      free(encrypted_filename_buffer); encrypted_filename_buffer = NULL;
      bytes_read = fread(&encrypted_val, 1, sizeof(unsigned int), input_file);
      if (bytes_read < sizeof(unsigned int)) {
        if (ferror(input_file)) sys_fail_helper("Error reading v1 file size", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated before v1 file size: %s", target_path_c);
        goto cleanup;
      }
      entry_file_size = decrypt_integer_v1(encrypted_val, &current_key_v1);
      file_data_key = current_key_v1;
      file_offset = 0;

    } else { // RGSSADv3 or Fux2Pack2
      unsigned int metadata_block[4];
      metadata_read_pos = ftell(input_file);
      if (metadata_read_pos == -1) { sys_fail_helper("Failed to get file position before v3/Fux2 metadata", target_path_c); goto cleanup; }
      bytes_read = fread(metadata_block, sizeof(unsigned int), 4, input_file);
      if (bytes_read < 4) {
        if (feof(input_file) && bytes_read == 0) break;
        if (ferror(input_file)) sys_fail_helper("Error reading v3/Fux2 metadata block", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated before/during v3/Fux2 metadata block: %s", target_path_c);
        goto cleanup;
      }
      file_offset = decrypt_integer_v3(metadata_block[0], metadata_key_v3);
      entry_file_size = decrypt_integer_v3(metadata_block[1], metadata_key_v3);
      file_data_key = decrypt_integer_v3(metadata_block[2], metadata_key_v3);
      filename_size = decrypt_integer_v3(metadata_block[3], metadata_key_v3);
      if (file_offset == 0) break;
      if (filename_size == 0 || filename_size > 1024 * 1024) {
        rb_raise(rgssad_extractor_RGSSADFileError_class, "Invalid v3/Fux2 filename size (%u): %s", filename_size, target_path_c);
        goto cleanup;
      }
      encrypted_filename_buffer = (unsigned char *)malloc(filename_size);
      if (!encrypted_filename_buffer) { sys_fail_helper("Failed to allocate buffer for v3/Fux2 filename", target_path_c); goto cleanup; }
      bytes_read = fread(encrypted_filename_buffer, 1, filename_size, input_file);
      if (bytes_read < filename_size) {
        if (ferror(input_file)) sys_fail_helper("Error reading v3/Fux2 filename data", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated during v3/Fux2 filename read: %s", target_path_c);
        goto cleanup;
      }
      if (verbose) printf("\e[34mDecrypting DataName...\r");
      decrypt_filename_v3(encrypted_filename_buffer, filename_size, metadata_key_v3);
      decrypted_filename_c = (char *)malloc(filename_size + 1);
      if (!decrypted_filename_c) { sys_fail_helper("Failed to allocate buffer for decrypted v3/Fux2 filename", target_path_c); goto cleanup; }
      memcpy(decrypted_filename_c, encrypted_filename_buffer, filename_size);
      decrypted_filename_c[filename_size] = '\0';
      free(encrypted_filename_buffer); encrypted_filename_buffer = NULL;
    }

    for (unsigned int i = 0; i < filename_size; ++i) {
      if (decrypted_filename_c[i] == '\\') decrypted_filename_c[i] = '/';
    }

    const char *log_filename = decrypted_filename_c;
#ifdef _WIN32
    if (utf8_to_wchar(decrypted_filename_c, filename_size) == -1) {}
    log_filename = (const char *)wchar_buffer;
#else
    if (utf8_to_mb(decrypted_filename_c, filename_size) == -1) {}
    log_filename = char_buffer;
#endif

    if (verbose) {
#ifdef _WIN32
      printf("\e[2K\e[32mDecrypting \e[0m%ls \e[0m%sOffset: \e[35m%u \e[0mSize: \e[35m%u \e[0mMagicKey: \e[35m%u\e[0m...\r", (wchar_t *)log_filename, (archive_type != RGSSADv1 ? "" : "(No Offset) "), file_offset, entry_file_size, file_data_key);
#else
      printf("\e[2K\e[32mDecrypting \e[0m%s \e[0m%sOffset: \e[35m%u \e[0mSize: \e[35m%u \e[0mMagicKey: \e[35m%u\e[0m...\r", log_filename, (archive_type != RGSSADv1 ? "" : "(No Offset) "), file_offset, entry_file_size, file_data_key);
#endif
    }

    VALUE rb_filename_str = rb_utf8_str_new(decrypted_filename_c, filename_size);
    VALUE output_full_path_rb = rb_funcall(rgssad_extractor_File_module, rgssad_extractor_join_id, 2, output_dir_rb, rb_filename_str); // Use new IDs/modules
    VALUE output_dir_part_rb = rb_funcall(rgssad_extractor_File_module, rgssad_extractor_dirname_id, 1, output_full_path_rb); // Use new IDs/modules
    rb_funcall(rgssad_extractor_FileUtils_module, rgssad_extractor_mkdir_p_id, 1, output_dir_part_rb); // Use new IDs/modules
    char *output_full_path_c = StringValueCStr(output_full_path_rb);

    if (entry_file_size > 0) {
      entry_data_buffer = (unsigned char *)malloc(entry_file_size);
      if (!entry_data_buffer) { sys_fail_helper("Failed to allocate buffer for file data", output_full_path_c); goto cleanup; }
      if (archive_type != RGSSADv1) {
        if (fseek(input_file, (long)file_offset, SEEK_SET) != 0) { sys_fail_helper("Failed to seek to file data offset", target_path_c); goto cleanup; }
      }
      bytes_read = fread(entry_data_buffer, 1, entry_file_size, input_file);
      if (bytes_read < entry_file_size) {
        if (ferror(input_file)) sys_fail_helper("Error reading file data", target_path_c);
        else rb_raise(rgssad_extractor_RGSSADFileError_class, "Truncated reading file data for: %s", decrypted_filename_c);
        goto cleanup;
      }
      decrypt_file_data(entry_data_buffer, entry_file_size, file_data_key);
    }

    if (verbose) {
#ifdef _WIN32
      printf("\e[2K\e[32mDecrypted \e[0m%ls \e[0m%sOffset: \e[35m%u \e[0mSize: \e[35m%u \e[0mMagicKey: \e[35m%u\e[0m\n", (wchar_t *)log_filename, (archive_type != RGSSADv1 ? "" : "(No Offset) "), file_offset, entry_file_size, file_data_key);
#else
      printf("\e[2K\e[32mDecrypted \e[0m%s \e[0m%sOffset: \e[35m%u \e[0mSize: \e[35m%u \e[0mMagicKey: \e[35m%u\e[0m\n", log_filename, (archive_type != RGSSADv1 ? "" : "(No Offset) "), file_offset, entry_file_size, file_data_key);
#endif
    }

    const char *log_output_filename = output_full_path_c;
#ifdef _WIN32
    if (utf8_to_wchar(output_full_path_c, strlen(output_full_path_c)) == -1) {}
    log_output_filename = (const char *)wchar_buffer;
#else
    if (utf8_to_mb(output_full_path_c, strlen(output_full_path_c)) == -1) {}
    log_output_filename = char_buffer;
#endif

    if (verbose) {
#ifdef _WIN32
      printf("\e[34mWriting \e[0m%ls...\r", (wchar_t *)log_output_filename);
#else
      printf("\e[34mWriting \e[0m%s...\r", log_output_filename);
#endif
    }

    output_file = platform_fopen(output_full_path_c, "wb");
    if (!output_file) { sys_fail_helper("Failed to open output file", output_full_path_c); goto cleanup; }
    if (entry_file_size > 0) {
      size_t bytes_written = fwrite(entry_data_buffer, 1, entry_file_size, output_file);
      if (bytes_written < entry_file_size) { sys_fail_helper("Failed to write all data to output file", output_full_path_c); goto cleanup; }
    }
    if (fclose(output_file) == EOF) { output_file = NULL; sys_fail_helper("Failed to close output file", output_full_path_c); goto cleanup; }
    output_file = NULL;

    if (verbose) {
#ifdef _WIN32
      printf("\e[2K\e[32mWrote \e[0m%ls\n", (wchar_t *)log_output_filename); // Changed "Writed" to "Wrote"
#else
      printf("\e[2K\e[32mWrote \e[0m%s\n", log_output_filename);             // Changed "Writed" to "Wrote"
#endif
    }

    free(decrypted_filename_c); decrypted_filename_c = NULL;
    free(entry_data_buffer); entry_data_buffer = NULL;

    if (archive_type != RGSSADv1) {
      long next_metadata_pos = metadata_read_pos + (sizeof(unsigned int) * 4) + filename_size;
      if (fseek(input_file, next_metadata_pos, SEEK_SET) != 0) {
        sys_fail_helper("Failed to seek back to next metadata position", target_path_c);
        goto cleanup;
      }
    }
  }

cleanup:
  if (input_file) fclose(input_file);
  if (output_file) fclose(output_file);
  free(entry_data_buffer);
  free(encrypted_filename_buffer);
  free(decrypted_filename_c);
#ifdef _WIN32
  free(wchar_buffer); wchar_buffer = NULL; wchar_buffer_size = 0;
#else
  free(char_buffer); char_buffer = NULL; char_buffer_size = 0;
#endif
  return Qnil;
}

/* Ruby Extension Initialization (Updated) */
void Init_rgssad_extractor() { // Renamed Init function
  RgssadExtractor_module = rb_define_module("RgssadExtractor"); // Define new module name

  // Get references to Ruby classes/modules using new variable names
  rgssad_extractor_File_module = rb_const_get(rb_cObject, rb_intern("File"));
  rgssad_extractor_FileUtils_module = rb_const_get(rb_cObject, rb_intern("FileUtils"));

  // Define or get the error class under the new module
  rgssad_extractor_RGSSADFileError_id = rb_intern("RGSSADFileError"); // ID for the error class name
  if (!rb_const_defined(RgssadExtractor_module, rgssad_extractor_RGSSADFileError_id)) {
    rgssad_extractor_RGSSADFileError_class =
        rb_define_class_under(RgssadExtractor_module, "RGSSADFileError", rb_eStandardError); // Define under new module
  } else {
    rgssad_extractor_RGSSADFileError_class = rb_const_get(RgssadExtractor_module, rgssad_extractor_RGSSADFileError_id); // Get from new module
  }

  // Get IDs for Ruby methods using new variable names
  rgssad_extractor_join_id = rb_intern("join");
  rgssad_extractor_dirname_id = rb_intern("dirname");
  rgssad_extractor_mkdir_p_id = rb_intern("mkdir_p");

  // Define the singleton method on the new module with the new name and C function
  rb_define_singleton_method(RgssadExtractor_module,        // Target module
                             "extract_archive",             // New Ruby method name
                             rgssad_extractor_extract_archive, // New C function name
                             3);                            // Arity (target_path, output_dir, verbose)
}