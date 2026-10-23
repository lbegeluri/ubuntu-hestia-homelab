#!/usr/bin/env bash
# get-status.sh — quick server summary.
#   ~/get-status.sh        basic (no sudo)
#   sudo ~/get-status.sh   + mail queue + top processes (/proc is hidepid)
LC_ALL=C
MAIL_HOST=${MAIL_HOST:-mail.example.com}   # host whose TLS certificate expiry is shown

if [ -t 1 ]; then G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'; else G=; Y=; R=; B=; D=; N=; fi
# colour by percentage: <70 green, <90 yellow, else red
col() { awk -v p="$1" -v g="$G" -v y="$Y" -v r="$R" 'BEGIN{print (p<70)?g:(p<90)?y:r}'; }

# --- CPU % (1 second sample of /proc/stat)
read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
idle=$(( (i2+w2) - (i1+w1) ))
total=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
cpu=$(awk -v i="$idle" -v t="$total" 'BEGIN{ if(t>0) printf "%.1f",(t-i)*100/t; else print "0.0"}')
cores=$(nproc)
read -r l1 l5 l15 _ < /proc/loadavg

# --- RAM / swap in GB (used = total - available)
read -r mt ma st sf < <(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}/SwapTotal/{s=$2}/SwapFree/{f=$2}END{print t,a,s,f}' /proc/meminfo)
ram_used=$(awk -v t="$mt" -v a="$ma" 'BEGIN{printf "%.2f",(t-a)/1048576}')
ram_tot=$(awk -v t="$mt" 'BEGIN{printf "%.2f",t/1048576}')
ram_pct=$(awk -v t="$mt" -v a="$ma" 'BEGIN{printf "%.0f",(t-a)*100/t}')
sw_used=$(awk -v t="$st" -v f="$sf" 'BEGIN{printf "%.2f",(t-f)/1048576}')
sw_tot=$(awk -v t="$st" 'BEGIN{printf "%.2f",t/1048576}')

# --- Disk (/) in GB
read -r dsize dused davail < <(df -B1 / | awk 'NR==2{print $2,$3,$4}')
d_tot=$(awk -v s="$dsize" 'BEGIN{printf "%.1f",s/1073741824}')
d_used=$(awk -v s="$dused" 'BEGIN{printf "%.1f",s/1073741824}')
d_free=$(awk -v s="$davail" 'BEGIN{printf "%.1f",s/1073741824}')
d_pct=$(awk -v u="$dused" -v s="$dsize" 'BEGIN{printf "%.0f",u*100/s}')

# --- CPU temperature (hottest readable thermal zone)
temp=""
for z in /sys/class/thermal/thermal_zone*/temp; do
  v=$(cat "$z" 2>/dev/null)
  case "$v" in ""|*[!0-9]*) continue;; esac
  t=$(( v / 1000 )); [ "$t" -gt "${temp:-0}" ] && temp=$t
done

echo "${B}== $(hostname -f) · $(date '+%F %H:%M') · up $(uptime -p | sed 's/^up //') ==${N}"
printf "%-5s %s%5s%%%s   load %s %s %s · %s cores\n" "CPU"  "$(col "$cpu")" "$cpu" "$N" "$l1" "$l5" "$l15" "$cores"
printf "%-5s %s%s / %s GB (%s%%)%s   swap %s / %s GB\n" "RAM" "$(col "$ram_pct")" "$ram_used" "$ram_tot" "$ram_pct" "$N" "$sw_used" "$sw_tot"
printf "%-5s %s%s / %s GB (%s%%)%s   free %s GB   (/)\n" "Disk" "$(col "$d_pct")" "$d_used" "$d_tot" "$d_pct" "$N" "$d_free"
[ -n "$temp" ] && printf "%-5s %s°C\n" "Temp" "$temp"

# --- Services
echo
printf "%s" "Services: "
for s in ssh nginx hestia exim4 dovecot mariadb fail2ban clamav-daemon; do
  systemctl cat "$s" >/dev/null 2>&1 || continue
  if systemctl is-active --quiet "$s"; then printf "%s ${G}✔${N}  " "$s"; else printf "%s ${R}✘${N}  " "$s"; fi
done
echo

# --- Mail queue / TLS cert / SSH probes / updates
if [ "$(id -u)" -eq 0 ]; then q=$(exim4 -bpc 2>/dev/null); else q=$(sudo -n exim4 -bpc 2>/dev/null); fi
[ -n "$q" ] && qtxt="$q queued" || qtxt="n/a (needs sudo)"
lan=$(hostname -I | awk '{print $1}')      # Hestia nginx listens on the LAN IP, not 127.0.0.1
end=$(echo | timeout 5 openssl s_client -connect "$lan":443 -servername "$MAIL_HOST" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$end" ]; then days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 )); ctxt="$days days"; [ "$days" -lt 14 ] && ctxt="${R}$days days — RENEW${N}"; else ctxt="n/a"; fi
if [ -r /var/log/auth.log ]; then ssh_bad=$(grep "^$(date +%F)" /var/log/auth.log | grep -cE "Invalid user|not allowed because|Failed (password|publickey)"); else ssh_bad="n/a"; fi
upd=$(/usr/lib/update-notifier/apt-check 2>&1 | tr ';' ' ')
if [ -n "$upd" ]; then set -- $upd; utxt="$1 pending ($2 security)"; else utxt="n/a"; fi
[ -f /var/run/reboot-required ] && rb="${Y}REBOOT REQUIRED${N}" || rb="no"
echo "Mail queue: $qtxt · TLS $MAIL_HOST: $ctxt · SSH probes today: $ssh_bad"
echo "Updates: $utxt · reboot: $rb"

# --- Top processes (needs root: /proc is mounted hidepid=invisible)
echo
if [ "$(id -u)" -eq 0 ]; then PS="ps"; else PS="sudo -n ps"; fi
n=$($PS -e --no-headers 2>/dev/null | wc -l)
if [ "$n" -gt 10 ]; then
  echo "${D}Top memory:${N} $($PS -eo comm,%mem --sort=-%mem --no-headers | head -3 | awk '{printf "%s %s%%  ", $1, $2}')"
  echo "${D}Top CPU:${N}    $($PS -eo comm,%cpu --sort=-%cpu --no-headers | head -3 | awk '{printf "%s %s%%  ", $1, $2}')"
else
  echo "${D}Top processes: n/a without root → sudo ~/get-status.sh${N}"
fi
