#!/usr/bin/env python3
# ==============================================================================
#  CTF flags falling trough map objects
# ==============================================================================
#
# This Python script automates the binary patch required to fix the "CTF Flag 
# falling trough map objects" bug, where the  flags always fall onto the map terrain,
# falling trough any buildings the player might stand on.
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
# 1. Save this file as 'patch_ctf_flags_map.py' inside your server's installation 
#    directory (e.g., ~/bf1942/).
#
# 2. Run the script using Python 3:
#    python3 patch_ctf_flags_map.py
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
                print(f"       Expected: {binascii.hexlify(orig_bytes).decode('utf-8')[:30]}...")
                print(f"       Found:    {binascii.hexlify(current_data).decode('utf-8')[:30]}...")
                print("       Aborting patch for this file to prevent corruption.")

    except IOError as e:
        print(f"[ERROR] Could not open/write file: {e}")
    print("\n")

# ==============================================================================
# DATA DEFINITIONS
# ==============================================================================

# File 1: bf1942_lnxded.static
static_file = "bf1942_lnxded.static"
static_offset = 0x249E80
static_orig = "D8 05 D0 E4 6B 08 58 8B 45 98 89 45 B8 5A 8B 45 9C 8B 55 08 89 45 BC 8B 45 A0 D9 45 AC D9 45 B0 89 45 C0 D9 45 C0 D9 45 BC D9 CC D9 5D DC D9 C2 D9 C2 D9 C9 D8 CA D9 45 A8 D9 CA D8 CE D9 45 B8 D9 CA DE E1 D9 C2 D9 CE D8 CA D9 CB D8 CF D9 C9 D9 55 C8 D9 CE D8 CC D9 C9 DE E3 D9 CC D8 C9 D9 C3 D8 CE D9 C9 DE E5 D9 C6 D9 CB D9 55 D0 DC CB D9 CD D9 55 CC D9 CD D8 CA D9 CC D8 CD D9 C9 DE E4 D9 C9 DE CC DE E9 D9 CC DE CB D9 5D AC DE E1 D9 C9 D9 5D A8 D9 5D B0"
static_new  = "d9 54 24 04 c7 04 24 00 02 00 02 8B 75 0C 8B 06 56 FF 50 3C 89 04 24 68 38 bb 71 08 6a c0 50 50 d8 63 34 d9 5c 24 00 50 8d 43 30 ff 70 08 ff 70 04 ff 30 83 ec 20 8d 44 24 38 50 83 e8 0c 50 83 e8 0c 50 83 e8 04 50 83 e8 0c 50 83 e8 0c 50 83 e8 04 50 a1 24 dc 71 08 50 8b 08 ff 51 48 83 c4 20 84 c0 74 06 D9 44 24 08 eb 04 D9 44 24 44 a1 f0 35 74 08 50 8b 08 ff 51 5c dd e1 df e0 f6 c4 45 74 04 dd d8 eb 02 dd d9 d8 05 d0 e4 6b 08 D9 5D DC 83 c4 4c 8B 55 08"

# File 2: bf1942_lnxded.dynamic
dynamic_file = "bf1942_lnxded.dynamic"
dynamic_offset = 0x250EF0
dynamic_orig = "D8 05 D0 27 67 08 58 8B 45 98 89 45 B8 5A 8B 45 9C 8B 55 08 89 45 BC 8B 45 A0 D9 45 AC D9 45 B0 89 45 C0 D9 45 C0 D9 45 BC D9 CC D9 5D DC D9 C2 D9 C2 D9 C9 D8 CA D9 45 A8 D9 CA D8 CE D9 45 B8 D9 CA DE E1 D9 C2 D9 CE D8 CA D9 CB D8 CF D9 C9 D9 55 C8 D9 CE D8 CC D9 C9 DE E3 D9 CC D8 C9 D9 C3 D8 CE D9 C9 DE E5 D9 C6 D9 CB D9 55 D0 DC CB D9 CD D9 55 CC D9 CD D8 CA D9 CC D8 CD D9 C9 DE E4 D9 C9 DE CC DE E9 D9 CC DE CB D9 5D AC DE E1 D9 C9 D9 5D A8 D9 5D B0"
dynamic_new  = "d9 54 24 04 c7 04 24 00 02 00 02 8B 75 0C 8B 06 56 FF 50 3C 89 04 24 68 38 96 6c 08 31 c0 50 50 d8 63 34 d9 5c 24 00 50 8d 43 30 ff 70 08 ff 70 04 ff 30 83 ec 20 8d 44 24 38 50 83 e8 0c 50 83 e8 0c 50 83 e8 04 50 83 e8 0c 50 83 e8 0c 50 83 e8 04 50 a1 24 b7 6c 08 50 8b 08 ff 51 48 83 c4 20 84 c0 74 06 D9 44 24 08 eb 04 D9 44 24 44 a1 f0 10 6f 08 50 8b 08 ff 51 5c dd e1 df e0 f6 c4 45 74 04 dd d8 eb 02 dd d9 d8 05 D0 27 67 08 D9 5D DC 83 c4 4c 8B 55 08"

# ==============================================================================
# EXECUTION
# ==============================================================================

if __name__ == "__main__":
    patch_file(static_file, static_offset, static_orig, static_new)
    patch_file(dynamic_file, dynamic_offset, dynamic_orig, dynamic_new)