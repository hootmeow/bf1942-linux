#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script (Fedora)
#
#  Target release:
#    - Fedora 44 (installation validation pending)
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./fed_44_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./fed_44_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./fed_44_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / https://captheflag.com)
# ---------------------------------------------------------------------------
