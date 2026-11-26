#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script (Debian)
#
#  Tested on:
#    - Debian 12 (Bookworm)
#    - Debian 13 (Trixie)
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./deb_12_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./deb_12_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./deb_12_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / https://captheflag.com)
# ---------------------------------------------------------------------------
