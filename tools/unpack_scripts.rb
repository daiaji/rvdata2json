#!/usr/bin/env ruby
# coding: utf-8
# Purpose: Unpack Scripts.rvdata from RPG Maker VX projects using numeric
#          filenames and storing original names (assumed UTF-8) in YAML.
#          Accepts command-line arguments for input file and output directory.

require "zlib"
require "fileutils"
require "psych" # For YAML output
require "optparse" # For command-line argument parsing

# --- Default Configuration ---
DEFAULT_INPUT_FILE = "Data/Scripts.rvdata"
DEFAULT_OUTPUT_DIR = "/home/daiaji/工程/脚本/Scripts_unpacked_numeric"
# The encoding we assume the original script names are in
ASSUMED_ENCODING = "UTF-8"
# ---------------------------

# --- Command Line Option Parsing ---
options = {
  input_file: DEFAULT_INPUT_FILE,
  output_dir: DEFAULT_OUTPUT_DIR,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator ""
  opts.separator "Specific options:"

  opts.on("-i", "--input FILE", "Path to the Scripts.rvdata file (default: #{DEFAULT_INPUT_FILE})") do |file|
    options[:input_file] = file
  end

  opts.on("-o", "--output DIR", "Path to the output directory (default: #{DEFAULT_OUTPUT_DIR})") do |dir|
    options[:output_dir] = dir
  end

  opts.on_tail("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV) # The '!' modifies ARGV, removing recognized options
rescue OptionParser::MissingArgument => e
  puts "Error: #{e.message}"
  puts parser # Show help on error
  exit 1
rescue OptionParser::InvalidOption => e
  puts "Error: #{e.message}"
  puts parser # Show help on error
  exit 1
end

# Use parsed options or defaults
scripts_rvdata_file = options[:input_file]
output_directory = options[:output_dir]
metadata_filename = File.join(output_directory, "_metadata.yaml")

# --- Script Logic ---

# Check if input file exists
unless File.exist?(scripts_rvdata_file)
  puts "Error: Input file not found: #{scripts_rvdata_file}"
  exit 1
end

# Create output directory if it doesn't exist
begin
  FileUtils.mkdir_p(output_directory) unless File.directory?(output_directory)
rescue Errno::EACCES, Errno::ENOENT => e
  puts "Error: Could not create output directory '#{output_directory}'. Please check permissions or path validity."
  puts "System Error: #{e.message}"
  exit 1
rescue => e
  puts "Error: An unexpected error occurred while creating directory '#{output_directory}': #{e.class} - #{e.message}"
  exit 1
end

puts "Input file:       #{scripts_rvdata_file}"
puts "Output directory:   #{output_directory}"
puts "Metadata file:    #{metadata_filename}"

# Initialize data structures
script_metadata = {} # Hash to store metadata: { "001.rb" => { original_name: "...", original_id: ... }, ... }
script_counter = 0   # Counter for numeric filenames

begin
  # Load the marshalled data (array of script data)
  # Read in binary mode ('rb') which is essential for Marshal
  puts "Loading #{scripts_rvdata_file}..."
  script_array = File.open(scripts_rvdata_file, "rb") do |file|
    Marshal.load(file)
  end

  puts "Unpacking scripts..."
  script_array.each_with_index do |script_data, index|
    # Each element is typically [id, name, compressed_script]
    unless script_data.is_a?(Array) && script_data.length >= 3
      puts "Warning: Skipping unexpected data structure at index #{index}"
      next
    end

    script_id = script_data[0] # Usually the internal ID
    original_name = script_data[1] # This string holds the raw bytes from Marshal
    compressed_script = script_data[2]

    # Skip entries with no name or empty compressed data
    # (Checking compressed_script too might be useful for some edge cases)
    if original_name.nil? || original_name.empty? #|| compressed_script.nil? || compressed_script.empty?
      puts "Skipping script with no name (Original Index: #{index}, ID: #{script_id || "N/A"})"
      next
    end

    # Increment counter *only* for scripts we are actually saving
    script_counter += 1

    # Generate the numeric filename
    numeric_filename = sprintf("%03d.rb", script_counter)
    output_filepath = File.join(output_directory, numeric_filename)

    # --- Prepare Original Name for Metadata (assuming UTF-8) ---
    utf8_name = "[Conversion Error]" # Default in case of failure
    begin
      # Ensure the string is treated as UTF-8.
      # Use .encode to validate and handle potential invalid byte sequences if they exist,
      # even though we assume the source is already UTF-8. This is safer.
      # .dup is important before force_encoding/encode if original_name might be used elsewhere unmodified.
      utf8_name = original_name.dup.force_encoding(ASSUMED_ENCODING).encode("UTF-8", invalid: :replace, undef: :replace, replace: "?") # Use '?' for replacements

      # Minor check: If the result is empty after replacement, use a placeholder
      utf8_name = "[Empty After Replace]" if utf8_name.empty? && !original_name.empty?
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
      puts "Warning: Could not process script name bytes as #{ASSUMED_ENCODING} for metadata (ID: #{script_id}, Index: #{index}). Storing placeholder. Error: #{e.message}"
      utf8_name = "[Encoding Error: #{e.message}]"
    rescue => e # Catch other potential errors
      puts "Warning: Error processing script name (ID: #{script_id}, Index: #{index}) for metadata. Storing placeholder. Error: #{e.class} - #{e.message}"
      utf8_name = "[Processing Error: #{e.message}]"
    end
    # -----------------------------------------------------------

    # Store metadata
    script_metadata[numeric_filename] = {
      "original_name_utf8" => utf8_name,
      # 'assumed_encoding' => ASSUMED_ENCODING, # Optionally store the assumption
      "original_id" => script_id,
      "original_index" => index,
    }

    # Decompress and write script content
    begin
      unless compressed_script.nil? || compressed_script.empty?
        script_content = Zlib::Inflate.inflate(compressed_script)
        File.open(output_filepath, "wb") do |out_file|
          out_file.write(script_content)
        end
        puts "  Unpacked -> #{output_filepath} (Original Name: #{utf8_name})"
      else
        puts "  Skipping writing empty script -> #{output_filepath} (Original Name: #{utf8_name})"
        # Create an empty file to maintain numbering consistency, or add an 'empty' flag to metadata
        FileUtils.touch(output_filepath) # Creates an empty file
        script_metadata[numeric_filename]["status"] = "Empty script data"
      end
    rescue Zlib::DataError => e
      puts "Error: Failed to decompress script for #{numeric_filename} (Original Name: #{utf8_name}). Zlib error: #{e.message}"
      script_metadata[numeric_filename]["error"] = "Zlib Decompression Failed: #{e.message}"
      FileUtils.rm_f(output_filepath) # Clean up potentially partially written file
    rescue Errno::ENOENT, Errno::EACCES => e
      puts "Error: Could not write file #{output_filepath}. Error: #{e.message}"
      script_metadata[numeric_filename]["error"] = "File Write Failed: #{e.message}"
    rescue => e # Catch other potential errors
      puts "Error: An unexpected error occurred while processing script for #{numeric_filename}: #{e.class} - #{e.message}"
      script_metadata[numeric_filename]["error"] = "Unexpected Error: #{e.class} - #{e.message}"
      puts e.backtrace.join("\n")
      FileUtils.rm_f(output_filepath) # Clean up potentially partially written file
    end
  end

  # Write the metadata hash to the YAML file
  puts "Writing metadata to #{metadata_filename}..."
  begin
    File.open(metadata_filename, "w:UTF-8") do |yaml_file|
      # Use Psych.dump with specific options for better readability if needed
      # e.g., Psych.dump(script_metadata, yaml_file, line_width: -1) # Prevent line wrapping
      yaml_file.write(Psych.dump(script_metadata))
    end
    puts "Metadata file created successfully."
  rescue Errno::ENOENT, Errno::EACCES => e
    puts "Error: Failed to write metadata file #{metadata_filename}. Error: #{e.message}"
  rescue => e
    puts "Error: An unexpected error occurred while writing metadata file #{metadata_filename}. Error: #{e.class} - #{e.message}"
  end

  puts "Script unpacking finished!"
  puts "Total scripts processed and saved: #{script_counter}"
rescue Marshal::LoadError => e
  puts "Error: Failed to load Marshal data from #{scripts_rvdata_file}."
  puts "This might mean the file is corrupt, not a valid Marshal file, or contains classes unknown to this Ruby environment."
  puts "Error details: #{e.message}"
  exit 1
rescue Errno::ENOENT => e # Catch file not found specifically for the input file during open
  puts "Error: Input file '#{scripts_rvdata_file}' not found or could not be opened."
  puts "System Error: #{e.message}"
  exit 1
rescue => e # Catch other potential errors during loading or setup
  puts "An unexpected error occurred: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
