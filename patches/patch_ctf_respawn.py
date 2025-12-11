#!/usr/bin/env python3
# ==============================================================================
#  CTF Flag Respawn Fix
# ==============================================================================
#
# This Python script automates the binary patch required to fix the "CTF Flag 
# Respawn" bug, where the respawn counter fails to reset if a flag is picked 
# up or dropped.
#
# Original Patch Credit: UUUZbf (https://github.com/uuuzbf/bf1942-patches)
#
# ------------------------------------------------------------------------------
#  IMPORTANT PREREQUISITES
# ------------------------------------------------------------------------------
# 1. Stop the Server: Do NOT run this patch while the bf1942 server process 
#    is running.
# 2. Backup Files: It is highly recommended to backup your 
#    'bf1942_lnxded.static' and 'bf1942_lnxded.dynamic' files before proceeding.
#
# ------------------------------------------------------------------------------
#  USAGE INSTRUCTIONS
# ------------------------------------------------------------------------------
# 1. Save this file as 'patch_ctf_respawn.py' inside your server's installation 
#    directory (e.g., ~/bf1942/).
#
# 2. Run the script using Python 3:
#    python3 patch_ctf_respawn.py
#
# 3. The script will output [SUCCESS] if the patch was applied correctly.
#    You may then restart your server.
#
# ==============================================================================

import os
import binascii

def patch_file(filename, offset, original_hex, new_hex):
    print(f"--- Processing {filename} ---")
    
    if not os.path.exists(filename):
        print(f"[ERROR] File not found: {filename}")
        return

    # Convert hex strings to bytes
    try:
        orig_bytes = binascii.unhexlify(original_hex.replace(" ", ""))
        new_bytes = binascii.unhexlify(new_hex.replace(" ", ""))
    except binascii.Error as e:
        print(f"[ERROR] Invalid hex data in script: {e}")
        return

    # Length check
    if len(orig_bytes) != len(new_bytes):
        print(f"[WARNING] Replacement length ({len(new_bytes)}) does not match original length ({len(orig_bytes)}).")
    
    # Open file in Read+Update Binary mode
    try:
        with open(filename, "r+b") as f:
            # 1. Go to the offset
            f.seek(offset)
            
            # 2. Read the current bytes to verify
            current_data = f.read(len(orig_bytes))
            
            # 3. Compare
            if current_data == orig_bytes:
                print(f"[OK] Original bytes match at offset 0x{offset:X}.")
                
                # 4. Write new bytes
                f.seek(offset)
                f.write(new_bytes)
                print(f"[SUCCESS] Patched {filename}.")
            
            elif current_data == new_bytes:
                print(f"[INFO] File appears to be ALREADY PATCHED. No changes made.")
                
            else:
                print(f"[FAIL] Byte mismatch at offset 0x{offset:X}!")
                print(f"       Expected: {binascii.hexlify(orig_bytes).decode('utf-8')}")
                print(f"       Found:    {binascii.hexlify(current_data).decode('utf-8')}")
                print("       Aborting patch for this file to prevent corruption.")

    except IOError as e:
        print(f"[ERROR] Could not open/write file: {e}")
    print("\n")

# ==============================================================================
# DATA DEFINITIONS - CTF Flag Respawn Fix
# ==============================================================================

# File 1: bf1942_lnxded.static
static_file = "bf1942_lnxded.static"
static_offset = 0x249DCD
static_orig = "50 56 E8 EC 0C DC FF 5A 59 50 A1 18 D9 70 08 50 FF 53 68 83 C4 20 EB A8 90 8D 76 00"
static_new  = "56 50 ff 53 68 8b 5d 08 8b 43 4c 8b 80 70 01 00 00 89 83 1c 01 00 00 83 c4 20 eb a4"

# File 2: bf1942_lnxded.dynamic
dynamic_file = "bf1942_lnxded.dynamic"
dynamic_offset = 0x250E3D
dynamic_orig = "50 56 E8 EC 0C DC FF 5A 59 50 A1 18 B4 6B 08 50 FF 53 68 83 C4 20 EB A8 90 8D 76 00"
dynamic_new  = "56 50 ff 53 68 8b 5d 08 8b 43 4c 8b 80 70 01 00 00 89 83 1c 01 00 00 83 c4 20 eb a4"

# ==============================================================================
# EXECUTION
# ==============================================================================

if __name__ == "__main__":
    patch_file(static_file, static_offset, static_orig, static_new)
    patch_file(dynamic_file, dynamic_offset, dynamic_orig, dynamic_new)