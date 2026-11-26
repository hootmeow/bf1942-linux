#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script
#  Ubuntu 22.04 LTS
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./ubu_22.04_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./ubu_22.04_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./ubu_22.04_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / https://captheflag.com)
# ---------------------------------------------------------------------------
