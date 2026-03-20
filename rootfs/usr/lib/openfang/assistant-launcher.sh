#!/bin/bash
# OpenFang AI Assistant — Interactive terminal launcher

CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'
BOLD='\033[1m'

clear
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║             OpenFang AI Assistant                    ║"
echo "  ║   Powered by OpenFang Agent Runtime                  ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Check if OpenFang API is up
if ! curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠  OpenFang agent runtime is not running.${RESET}"
    echo "  Start it with: sudo systemctl start openfang"
    echo
fi

echo -e "  Type your question below. Type ${BOLD}exit${RESET} to quit."
echo -e "  ${CYAN}────────────────────────────────────────────────────${RESET}"
echo

while true; do
    echo -en "${GREEN}You:${RESET} "
    read -r question
    [ -z "${question}" ] && continue
    [[ "${question,,}" =~ ^(exit|quit|bye|q)$ ]] && { echo "Goodbye!"; break; }

    echo
    echo -en "${CYAN}AI:${RESET}  "

    # Try OpenFang API first
    if curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
        response=$(curl -sf \
            -X POST http://127.0.0.1:8080/ask \
            -H "Content-Type: application/json" \
            -d "{\"question\": $(echo "${question}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}" \
            2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("answer",""))' 2>/dev/null)

        if [ -n "${response}" ]; then
            echo "${response}"
        else
            echo -e "${YELLOW}(Could not get response from API)${RESET}"
        fi
    else
        echo -e "${YELLOW}OpenFang API offline. Configure with: openfang-ctl config edit${RESET}"
    fi

    echo
done
