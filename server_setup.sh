➜  ~ ssh -xY deck@10.0.0.77
deck@10.0.0.77's password:
Last login: Mon Apr  6 18:48:37 2026 from 10.0.0.3
(deck@steamdeck ~)$ cat ~/server_setup.sh
#!/bin/bash
set -e

CONFIG_BASE="$HOME/.config"
STREMIO_DIR="$HOME/.stremio-server"

# Ensure /dev/net/tun exists
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# Create persistent directories
mkdir -p "$CONFIG_BASE/tailscale" "$STREMIO_DIR" "$CONFIG_BASE/portal/www"

# Fix permissions for Stremio volume so login persists
sudo chown -R 1000:1000 "$STREMIO_DIR"

# Remove old containers
sudo podman rm -f tailscale stremio-server portal 2>/dev/null || true

# Start Tailscale
sudo podman run -d --name tailscale --network host --replace --restart always \
  --privileged \
  -v "$CONFIG_BASE/tailscale":/var/lib/tailscale:Z \
  docker.io/tailscale/tailscale:latest

# Bring up Tailscale (login needed first time)
sudo podman exec tailscale tailscale up --accept-dns --accept-routes --ssh --reset || echo "Tailscale may need manual login"

# ===== Wait for full MagicDNS hostname =====
FULL_HOSTNAME=""
echo "Waiting for Tailscale MagicDNS hostname..."
for i in {1..30}; do
    FULL_HOSTNAME=$(sudo podman exec tailscale tailscale status --json 2>/dev/null \
                    | jq -r '.Self.DNSName // empty')
    FULL_HOSTNAME=${FULL_HOSTNAME%.}
    if [ -n "$FULL_HOSTNAME" ]; then
        break
    fi
    sleep 2
done

if [ -z "$FULL_HOSTNAME" ]; then
    FULL_HOSTNAME="steamdeck"
fi

# Grab Tailscale IPv4
TS_IP=$(sudo podman exec tailscale tailscale ip -4 2>/dev/null || echo "127.0.0.1")

# ===== Write portal HTML =====
cat > "$CONFIG_BASE/portal/www/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Steam Deck Portal</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: sans-serif; text-align: center; padding: 50px; background: #121212; color: white; }
        .card { background: #1e1e1e; padding: 20px; border-radius: 10px; display: inline-block; margin-top: 20px; }
        input { width: 300px; padding: 10px; font-size: 1em; text-align: center; border-radius: 5px; border: none; margin-bottom: 10px; }
        button { padding: 10px 20px; margin: 5px; border-radius: 5px; border: none; background: #3f51b5; color: white; font-size: 1em; cursor: pointer; }
        button:hover { background: #5a67d8; }
    </style>
</head>
<body>
    <h1>Steam Deck Portal</h1>

    <h3>Stremio Web (MagicDNS)</h3>
    <div class="card">
        <input type="text" readonly value="http://$FULL_HOSTNAME:11470" id="stremio-dns-url">
        <br>
        <button onclick="window.location.href='http://$FULL_HOSTNAME:11470'">Open Stremio</button>
        <button onclick="copyText('stremio-dns-url')">Copy URL</button>
    </div>

    <h3>Stremio Web (Tailscale IP)</h3>
    <div class="card">
        <input type="text" readonly value="http://$TS_IP:11470" id="stremio-ip-url">
        <br>
        <button onclick="window.location.href='http://$TS_IP:11470'">Open Stremio</button>
        <button onclick="copyText('stremio-ip-url')">Copy URL</button>
    </div>

    <h3>SSH / Ping (MagicDNS)</h3>
    <div class="card">
        <input type="text" readonly value="$FULL_HOSTNAME" id="host-dns">
        <br>
        <button onclick="copyText('host-dns')">Copy Hostname</button>
        <button onclick="copySSH('host-dns')">Copy SSH Command</button>
        <button onclick="copyPing('host-dns')">Copy Ping Command</button>
    </div>

    <h3>SSH / Ping (Tailscale IP)</h3>
    <div class="card">
        <input type="text" readonly value="$TS_IP" id="host-ip">
        <br>
        <button onclick="copyText('host-ip')">Copy IP</button>
        <button onclick="copySSH('host-ip')">Copy SSH Command</button>
        <button onclick="copyPing('host-ip')">Copy Ping Command</button>
    </div>

    <p style="margin-top: 20px; font-size: 0.9em; color: #888;">
        Note: SSH works only if <code>sshd</code> is running on the Steam Deck host.
    </p>

    <script>
        function copyText(id) {
            const text = document.getElementById(id).value;
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(text)
                    .then(() => alert('Copied: ' + text))
                    .catch(err => fallbackCopy(text));
            } else {
                fallbackCopy(text);
            }
        }

        function fallbackCopy(text) {
            const temp = document.createElement('textarea');
            temp.value = text;
            temp.style.position = 'fixed';
            temp.style.top = '-9999px';
            document.body.appendChild(temp);
            temp.focus();
            temp.select();
            try {
                document.execCommand('copy');
                alert('Copied: ' + text);
            } catch (err) {
                alert('Failed to copy: ' + err);
            }
            document.body.removeChild(temp);
        }

        function copySSH(id) {
            const host = document.getElementById(id).value;
            const cmd = 'ssh deck@' + host;
            navigator.clipboard.writeText(cmd)
                .then(() => alert('Copied SSH command: ' + cmd))
                .catch(() => fallbackCopy(cmd));
        }

        function copyPing(id) {
            const host = document.getElementById(id).value;
            const cmd = 'ping ' + host;
            navigator.clipboard.writeText(cmd)
                .then(() => alert('Copied ping command: ' + cmd))
                .catch(() => fallbackCopy(cmd));
        }
    </script>
</body>
</html>
EOF

# ===== Start portal =====
sudo podman run -d --name portal --replace --restart always \
  -p 80:80 \
  -v "$CONFIG_BASE/portal/www":/usr/share/nginx/html:Z \
  docker.io/library/nginx:alpine

# ===== Start Stremio =====
podman run -d --name stremio-server --replace --restart always \
  --network host \
  -v "$STREMIO_DIR":/root/.stremio-server:Z \
  --user 1000:1000 \
  docker.io/stremio/server:latest

echo "========================================================"
echo " PORTAL: http://localhost"
echo " TAILSCAPE (MagicDNS): http://$FULL_HOSTNAME"
echo "========================================================"
echo "IMPORTANT: Make sure SSH server is running on Steam Deck for Termius."
echo "You can enable it with: sudo systemctl enable sshd && sudo systemctl start sshd"
