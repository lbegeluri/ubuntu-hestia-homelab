
# Access Hestia web panel via SSH tunnel (keep opened)

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md)

```bash
ssh -L 8083:localhost:8083 sysadmin@203.0.113.10
```

- Keep this terminal **open** → tunnel lives as long as the session
- Browse to `https://localhost:8083` → accept the self-signed cert warning
- Login: `admin` + installer password
- Port 8083 is NOT forwarded on the router → panel never exposed to the internet
- LAN alternative: `https://192.168.1.50:8083`
- Reset admin password: `sudo /usr/local/hestia/bin/v-change-user-password admin NEWPASSWORD`

! Do not port-forward 8083 (scanner target + leaks real IP)
