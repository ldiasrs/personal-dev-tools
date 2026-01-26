#!/bin/bash

# Convert MPA to MP3 for WhatsApp
# Usage: convert-mpa-mp3-whatsapp.sh <input_file> <output_file>
# Example: convert-mpa-mp3-whatsapp.sh input.mpa output.mp3

#Check params and show help if needed
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: convert-mpa-mp3-whatsapp.sh <input_file> <output_file>"
    echo "Example: convert-mpa-mp3-whatsapp.sh input.mpa output.mp3"
    exit 1
fi

# Convert MPA to MP3
ffmpeg -i $1 -vn -ab 128k $2.mp3