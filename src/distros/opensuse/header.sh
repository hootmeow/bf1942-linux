#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script (openSUSE)
#
#  Target releases:
#    - openSUSE Leap 16
#    - openSUSE Tumbleweed / Slowroll
#
#  Features:
#    ✓ Native 32-bit libraries from the openSUSE repos (-32bit packages)
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./opensuse_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./opensuse_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./opensuse_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / https://captheflag.com)
# ---------------------------------------------------------------------------
