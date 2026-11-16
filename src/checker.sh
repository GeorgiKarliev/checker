#!/bin/bash

# Student name: Georgi Karliev
# Student code: s4
# Class code: TCB-2506
# Lecturers: Ivan Blagoev, Yuri Tsenkov


# ================================================
# COLORS
# ================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ================================================
# GLOBAL VARIABLES
# ================================================

# Main log file required by the project.
LOG_FILE="/var/log/checker_project.log"

# The scan network, selected target and selected attack will be saved here.
NETWORK=""
TARGET_IP=""
ATTACK_CHOICE=""

# Attack outputs will be saved in this folder.
RESULTS_DIR="checker_results"

# This array will store all active hosts found by Nmap.
HOSTS=()

# ================================================
# DISPLAY FUNCTIONS
# ================================================

show_stage() {
    echo
    echo -e "${CYAN}[*] $1${NC}"
    echo "----------------------------------------"
}

error_exit() {
    echo -e "${RED}[-] $1${NC}"
    echo -e "${RED}[-] Program terminated.${NC}"
    exit 1
}

# ================================================
# BASIC CHECKS
# ================================================

check_root() {
    # The script needs root because it writes to /var/log and uses hping3.
    USER_NAME=$(whoami)

    if [ "$USER_NAME" != "root" ]; then
        error_exit "Run the script with sudo."
    fi
}

check_tools() {
    show_stage "Checking tools"

    # This variable will collect all missing tools.
    MISSING=""

    # Check if Nmap is installed.
    if ! command -v nmap > /dev/null; then
        echo -e "${RED}[-] nmap is missing.${NC}"
        MISSING="$MISSING nmap"
    fi

    # Check if Hping3 is installed.
    if ! command -v hping3 > /dev/null; then
        echo -e "${RED}[-] hping3 is missing.${NC}"
        MISSING="$MISSING hping3"
    fi

    # Check if Hydra is installed.
    if ! command -v hydra > /dev/null; then
        echo -e "${RED}[-] hydra is missing.${NC}"
        MISSING="$MISSING hydra"
    fi

    # If nothing is missing, continue.
    # If something is missing, ask the user if it should be installed.
    if [ -z "$MISSING" ]; then
        echo -e "${GREEN}[+] All tools are installed.${NC}"
    else
        echo
        echo -e "${YELLOW}[!] Missing tools:$MISSING${NC}"
        read -p "Do you want to install them? y/n: " INSTALL_CHOICE

        if [ "$INSTALL_CHOICE" = "y" ]; then
            apt update
            apt install -y $MISSING
        else
            error_exit "Cannot continue without required tools."
        fi
    fi
}

setup_log() {
    # Create the log file in /var/log.
    touch "$LOG_FILE" 2>/dev/null

    # Check if the script can write to the log file.
    if [ ! -w "$LOG_FILE" ]; then
        error_exit "Cannot write to $LOG_FILE"
    fi

    echo -e "${GREEN}[+] Log file ready: $LOG_FILE${NC}"
}

setup_results_dir() {
    # Create a local folder for the output files from the tools.
    mkdir -p "$RESULTS_DIR"

    if [ ! -d "$RESULTS_DIR" ]; then
        error_exit "Cannot create results directory."
    fi

    echo -e "${GREEN}[+] Results directory ready: $RESULTS_DIR${NC}"
}

confirm_permission() {
    show_stage "Permission check"

    # Ask the user to confirm that the checks are authorized.
    echo -e "${YELLOW}[!] This script is only for authorized environments.${NC}"
    read -p "Do you have permission to run checks on this network? y/n: " PERMISSION

    if [ "$PERMISSION" != "y" ]; then
        error_exit "Permission not confirmed."
    fi

    echo -e "${GREEN}[+] Permission confirmed.${NC}"
}

# ================================================
# NETWORK AND HOSTS
# ================================================

validate_network() {
    # Accept format: 192.168.1.0/24
    if [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        return 0

    # Accept format: 192.168.1.0-255
    elif [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]; then
        return 0

    # Accept format: 192.168.1.*
    elif [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.\*$ ]]; then
        return 0

    # If none of the formats match, return error.
    else
        return 1
    fi
}

get_network() {
    show_stage "Network input"

    # Ask for network until the user enters a valid format.
    while true; do
        echo "Allowed formats:"
        echo "1. 192.168.1.0/24"
        echo "2. 192.168.1.0-255"
        echo "3. 192.168.1.*"
        echo

        read -p "Enter network: " NETWORK

        if validate_network; then
            echo -e "${GREEN}[+] Network accepted: $NETWORK${NC}"
            break
        else
            echo -e "${RED}[-] Invalid network format.${NC}"
            echo -e "${YELLOW}[!] Please enter the network in one of the allowed formats.${NC}"
            echo
        fi
    done
}

find_hosts() {
    show_stage "Finding available IP addresses"

    # Clear the HOSTS array before saving new results.
    HOSTS=()

    # Nmap finds active hosts.
    # awk extracts only the IP addresses from the grepable output.
    for IP in $(nmap -sn "$NETWORK" -oG - | awk '/Up$/{print $2}'); do
        HOSTS+=("$IP")
    done

    # Stop if no active hosts were found.
    if [ "${#HOSTS[@]}" -eq 0 ]; then
        error_exit "No active hosts found."
    fi

    echo -e "${GREEN}[+] Active hosts:${NC}"

    # Print the found hosts with numbers.
    COUNT=1
    for IP in "${HOSTS[@]}"; do
        echo "$COUNT. $IP"
        COUNT=$((COUNT + 1))
    done
}

# ================================================
# ATTACK MENU
# ================================================

show_attacks() {
    show_stage "Available attacks"

    # Show all attacks with short descriptions.
    echo -e "${GREEN}1. Nmap TCP Scan${NC}"
    echo -e "   ${YELLOW}Description:${NC} Scans common TCP ports on the target."

    echo
    echo -e "${GREEN}2. Hping3 ICMP Probe${NC}"
    echo -e "   ${YELLOW}Description:${NC} Sends a few ICMP packets to the target."

    echo
    echo -e "${GREEN}3. Hydra SSH Login Check${NC}"
    echo -e "   ${YELLOW}Description:${NC} Uses username list and password list to check SSH login."

    echo
    echo -e "${CYAN}r. Random attack${NC}"
}

choose_attack() {
    # Ask until the user chooses 1, 2, 3 or r.
    while true; do
        show_attacks

        read -p "Choose attack: " ATTACK_CHOICE

        # If the user chooses r, select a random attack from 1 to 3.
        if [ "$ATTACK_CHOICE" = "r" ]; then
            ATTACK_CHOICE=$((RANDOM % 3 + 1))
        fi

        # Check if the selected attack is valid.
        if [[ "$ATTACK_CHOICE" = "1" || "$ATTACK_CHOICE" = "2" || "$ATTACK_CHOICE" = "3" ]]; then
            case "$ATTACK_CHOICE" in
                1)
                    echo -e "${GREEN}[+] Selected attack: Nmap TCP Scan${NC}"
                    ;;
                2)
                    echo -e "${GREEN}[+] Selected attack: Hping3 ICMP Probe${NC}"
                    ;;
                3)
                    echo -e "${GREEN}[+] Selected attack: Hydra SSH Login Check${NC}"
                    ;;
            esac
            break
        else
            echo -e "${RED}[-] Invalid attack choice.${NC}"
            echo -e "${YELLOW}[!] Please choose 1, 2, 3 or r.${NC}"
            echo
        fi
    done
}

choose_target() {
    show_stage "Choose target"

    # Show all detected hosts.
    for i in "${!HOSTS[@]}"; do
        echo "$((i+1)). ${HOSTS[$i]}"
    done

    echo "r. Random target"
    read -p "Choose target: " TARGET_CHOICE

    # Select a random target.
    if [ "$TARGET_CHOICE" = "r" ]; then
        RANDOM_INDEX=$((RANDOM % ${#HOSTS[@]}))
        TARGET_IP="${HOSTS[$RANDOM_INDEX]}"

    # Select target by number.
    elif [ "$TARGET_CHOICE" -ge 1 ] 2>/dev/null && [ "$TARGET_CHOICE" -le "${#HOSTS[@]}" ]; then
        TARGET_IP="${HOSTS[$((TARGET_CHOICE-1))]}"

    # If the input is invalid, show the menu again.
    else
        echo -e "${RED}[-] Invalid target choice.${NC}"
        choose_target
        return
    fi

    echo -e "${GREEN}[+] Target selected: $TARGET_IP${NC}"
}

# ================================================
# LOGGING
# ================================================

log_attack() {
    STATUS="$1"
    ATTACK_NAME="$2"
    TIME_NOW=$(date "+%Y-%m-%d %H:%M:%S")

    # Save time, attack name, target IP and status into /var/log.
    echo "$TIME_NOW | attack=$ATTACK_NAME | target=$TARGET_IP | status=$STATUS" >> "$LOG_FILE"
}

# ================================================
# ATTACK 1: NMAP TCP SCAN
# ================================================

attack_nmap() {
    ATTACK_NAME="Nmap TCP Scan"
    OUTPUT_FILE="$RESULTS_DIR/checker_nmap_$TARGET_IP.txt"

    show_stage "$ATTACK_NAME"

    # Log that the attack has started.
    log_attack "STARTED" "$ATTACK_NAME"

    # Run a fast Nmap scan and save the result into a file.
    if nmap -F "$TARGET_IP" -oN "$OUTPUT_FILE"; then
        log_attack "FINISHED" "$ATTACK_NAME"
        echo -e "${GREEN}[+] Attack finished.${NC}"
        echo -e "${GREEN}[+] Result saved in: $OUTPUT_FILE${NC}"
    else
        log_attack "FAILED" "$ATTACK_NAME"
        echo -e "${RED}[-] Attack failed.${NC}"
    fi
}

# ================================================
# ATTACK 2: HPING3 ICMP PROBE
# ================================================

attack_hping3() {
	
	# This makes pipes return failed if the first command fails.
	# It is useful for hping3 | tee.
	set -o pipefail
	
    ATTACK_NAME="Hping3 ICMP Probe"
    OUTPUT_FILE="$RESULTS_DIR/checker_hping3_$TARGET_IP.txt"

    show_stage "$ATTACK_NAME"

    # Log that the ICMP probe has started.
    log_attack "STARTED" "$ATTACK_NAME"

    # Send 5 ICMP packets to the target.
    # tee shows the result on screen and saves it into a file.
    if hping3 -1 -c 5 "$TARGET_IP" 2>&1 | tee "$OUTPUT_FILE"; then
        log_attack "FINISHED" "$ATTACK_NAME"
        echo -e "${GREEN}[+] Attack finished.${NC}"
        echo -e "${GREEN}[+] Result saved in: $OUTPUT_FILE${NC}"
    else
        log_attack "FAILED" "$ATTACK_NAME"
        echo -e "${RED}[-] Attack failed.${NC}"
        echo -e "${YELLOW}[!] Result saved in: $OUTPUT_FILE${NC}"
    fi
}

# ================================================
# ATTACK 3: HYDRA SSH LOGIN CHECK
# ================================================

attack_hydra() {
    ATTACK_NAME="Hydra SSH Login Check"
    OUTPUT_FILE="$RESULTS_DIR/checker_hydra_$TARGET_IP.txt"

    show_stage "$ATTACK_NAME"

    # Hydra should be used only with permission.
    echo -e "${YELLOW}[!] Use Hydra only with permission.${NC}"
    read -p "Do you have permission to test SSH login on this target? y/n: " HYDRA_PERMISSION

    if [ "$HYDRA_PERMISSION" != "y" ]; then
        log_attack "SKIPPED" "$ATTACK_NAME"
        echo -e "${YELLOW}[!] Hydra check skipped.${NC}"
        return
    fi

    # Check if SSH port 22 is open before running Hydra.
    echo -e "${CYAN}[*] Checking if SSH port 22 is open...${NC}"

    if ! nmap -p 22 --open "$TARGET_IP" -oG - | grep -q "22/open"; then
        log_attack "SKIPPED_SSH_CLOSED" "$ATTACK_NAME"
        echo -e "${YELLOW}[!] SSH port 22 is not open. Hydra skipped.${NC}"
        return
    fi

    # Ask the user for username and password lists.
    read -p "Enter username list path: " USER_LIST
    read -p "Enter password list path: " PASSWORD_LIST

    # Check if the username list exists.
    if [ ! -f "$USER_LIST" ]; then
        error_exit "Username list file not found."
    fi

    # Check if the password list exists.
    if [ ! -f "$PASSWORD_LIST" ]; then
        error_exit "Password list file not found."
    fi

    # Log that the Hydra check has started.
    log_attack "STARTED" "$ATTACK_NAME"

    # Run Hydra with username list and password list against SSH.
    hydra -L "$USER_LIST" -P "$PASSWORD_LIST" ssh://"$TARGET_IP" -t 1 -f -o "$OUTPUT_FILE"

    # Check if Hydra finished successfully.
    if [ $? -eq 0 ]; then
        log_attack "FINISHED" "$ATTACK_NAME"
        echo -e "${GREEN}[+] Hydra check finished.${NC}"
        echo -e "${GREEN}[+] Result saved in: $OUTPUT_FILE${NC}"
    else
        log_attack "FAILED_OR_NO_LOGIN" "$ATTACK_NAME"
        echo -e "${YELLOW}[!] Hydra finished, but no valid login was found or an error occurred.${NC}"
        echo -e "${YELLOW}[!] Result saved in: $OUTPUT_FILE${NC}"
    fi
}

# ================================================
# EXECUTE ATTACK
# ================================================

execute_attack() {
    # Run the function that matches the selected attack.
    case "$ATTACK_CHOICE" in
        1)
            attack_nmap
            ;;
        2)
            attack_hping3
            ;;
        3)
            attack_hydra
            ;;
     # This is a safety check. Normally the script should not reach it,
	 # because the user input is already validated in choose_attack().
        *)
            error_exit "Unknown attack."
            ;;
    esac
}

# ================================================
# SHOW LAST LOGS
# ================================================

show_logs() {
    show_stage "Last log entries"

    # Show the last 10 lines from the project log.
    tail -n 10 "$LOG_FILE"
}

# ================================================
# MAIN
# ================================================

main() {
    clear

    echo "========================================"
    echo "               CHECKER"
    echo "========================================"
    echo "       Attack Simulation System"
    echo

    # Run initial checks and setup.
    check_root
    confirm_permission
    check_tools
    setup_log
    setup_results_dir

    # Get network and discover active hosts.
    get_network
    find_hosts

    # Allow the user to run multiple attacks.
    while true; do
        choose_attack
        choose_target
        execute_attack
        show_logs

        echo
        read -p "Run another attack? y/n: " AGAIN

		while [ "$AGAIN" != "y" ] && [ "$AGAIN" != "n" ]; do
			echo -e "${RED}[-] Invalid input. Please type y or n.${NC}"
			read -p "Run another attack? y/n: " AGAIN
		done

		if [ "$AGAIN" = "y" ]; then
			continue
		else
			echo -e "${GREEN}[+] Done.${NC}"
			echo -e "${GREEN}[+] Logs saved in: $LOG_FILE${NC}"
			break
		fi
	done
}

main
