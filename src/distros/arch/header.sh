#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Arch Linux Setup Script
#
#  Features:
#    ✓ Arch Linux native ([multilib] pacman integration)
#    ✓ Zero system downgrades (isolated local library shims)
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support & bf1942_manager.sh compatibility
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./arch_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./arch_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./arch_bfsmd_setup.sh --help
#
#  Author: OWLCAT (adapted for Arch Linux)
# ---------------------------------------------------------------------------
