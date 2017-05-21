# maxscript
Various scripts for 3ds Max we find helpful

# Photoshop
## convert_images_for_social.jsx
### Overview
A script that automatically resizes images for social media posting. It uses the recommendations as of May 2017 for image dimensions.
### Installation
There are a few different ways to run the script. In true Adobe fashion, none are particularly ideal.
1. On the Photoshop menu, choose File -> Scripts -> Browse and find the location where you saved the .jsx script file. Selecting the file there will run it.
2. If you have Administrator access to your computer, you can have the script show up in the File -> Scripts menu by saving it to Photoshop's Presets folder. There should be a folder called "Presets / Scripts" in your Photoshop installation folder (Applications on Mac, Program Files on Windows). Copy the file there and it will show up on the File -> Scripts menu.
3. Double click the .jsx file in your file browser. Adobe tends to mess up the file associations so this might not work reliably.
### Usage
1. The script operates on all the images you have open in Photoshop, so open all the images you want to convert and close all others.
2. Run the script using one of the methods described in Installation
3. For each output format for each file you will be given a crop window for formats that enforce the aspect ratio. Move the crop window as you like and press enter.
4. After each crop, the script will save a properly sized JPG file to the same location as the original file, with a suffix added such as "\_instagram" to indicate which format it is intended.
5. When the script is finished, it will restore your file to it's state just before running the script.
6. You're done! Post the images and use the extra time you saved by not manually resizing and renaming files to have a nice cup of tea.
**It is recommended that you save your file before running the script to avoid potentially losing changes made since your last save if the script fails**
