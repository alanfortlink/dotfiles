#!/bin/bash
set -e

CONFIG_BASE="$HOME/.config"
STREMIO_DIR="$HOME/.stremio-server"
MEDIA_DIR="/run/media/deck/X10 Pro"
JELLYFIN_DIR="$HOME/jellyfin/config"

# ===== Surfshark VPN credentials =====
# Get these from: my.surfshark.com > Manual Setup > OpenVPN
SURFSHARK_USER=""
SURFSHARK_PASS=""

# Clean rootful podman to keep / usage low
sudo podman system prune -f 2>/dev/null || true

# Ensure /dev/net/tun exists
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# Create persistent directories
mkdir -p "$CONFIG_BASE/tailscale" "$STREMIO_DIR" "$CONFIG_BASE/portal/www" \
         "$JELLYFIN_DIR" "$CONFIG_BASE/gluetun/auth" \
         "$CONFIG_BASE/prowlarr" "$CONFIG_BASE/sonarr" "$CONFIG_BASE/radarr" \
         "$CONFIG_BASE/qbittorrent"

# Allow unauthenticated access to gluetun control server
mkdir -p "$CONFIG_BASE/gluetun/auth"
cat > "$CONFIG_BASE/gluetun/auth/config.toml" <<'AUTHEOF'
[[roles]]
name = "public"
auth = "none"
routes = [
  "GET /v1/openvpn/status",
  "PUT /v1/openvpn/status",
  "GET /v1/openvpn/settings",
  "GET /v1/publicip/ip",
  "GET /v1/vpn/status",
  "PUT /v1/vpn/status",
  "PUT /v1/vpn/settings",
]
AUTHEOF

# Remove old containers (rootful: tailscale, portal; rootless: media stack + vpn)
sudo podman rm -f tailscale portal 2>/dev/null || true
podman rm -f gluetun qbittorrent jellyfin stremio-server prowlarr sonarr radarr 2>/dev/null || true

# Start Tailscale
sudo podman run -d --name tailscale --network host --replace --restart always \
  --privileged \
  -v "$CONFIG_BASE/tailscale":/var/lib/tailscale:Z \
  docker.io/tailscale/tailscale:latest

# Bring up Tailscale (login needed first time)
sudo podman exec tailscale tailscale up --accept-dns --accept-routes --ssh || echo "Tailscale may need manual login"

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

# Grab Tailscale IPv4
TS_IP=$(sudo podman exec tailscale tailscale ip -4 2>/dev/null | tr -d '[:space:]')
[ -z "$TS_IP" ] && TS_IP="127.0.0.1"

# Detect active exit node (if any)
EXIT_NODE=$(sudo podman exec tailscale tailscale status --json 2>/dev/null \
    | jq -r '[.Peer // {} | to_entries[] | select(.value.ExitNode == true) | .value.HostName] | .[0] // empty')
[ -z "$EXIT_NODE" ] && EXIT_NODE="Direct"

if [ -z "$FULL_HOSTNAME" ]; then
    FULL_HOSTNAME="$TS_IP"
fi

# ===== Write nginx config (proxy /api to gluetun) =====
cat > "$CONFIG_BASE/portal/nginx.conf" <<'NGINXEOF'
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
    }
    location /switch {
        proxy_pass http://127.0.0.1:9090;
        proxy_read_timeout 120;
    }
}
NGINXEOF

# ===== Write portal HTML =====
cat > "$CONFIG_BASE/portal/www/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <title>Steam Deck Portal</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        :root {
            --bg: #0b0d12;
            --bg-2: #11141b;
            --panel: #171a23;
            --panel-2: #1e2230;
            --border: #262b3a;
            --border-strong: #333a4d;
            --text: #eceef5;
            --muted: #8891a8;
            --accent: #7c9cff;
            --accent-hover: #97b2ff;
            --success: #4ade80;
            --warn: #fbbf24;
        }
        * { box-sizing: border-box; }
        html, body { height: 100%; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
            margin: 0; padding: 0; color: var(--text);
            background:
              radial-gradient(1200px 600px at 10% -10%, #1a2040 0%, transparent 60%),
              radial-gradient(900px 500px at 110% 10%, #1d1530 0%, transparent 55%),
              var(--bg);
            min-height: 100%;
        }
        .wrap { max-width: 1180px; margin: 0 auto; padding: 40px 24px 80px; }

        /* Header */
        header {
            display: flex; align-items: center; justify-content: space-between;
            flex-wrap: wrap; gap: 16px; margin-bottom: 32px;
        }
        .brand { display: flex; align-items: center; gap: 14px; }
        .logo {
            width: 44px; height: 44px; border-radius: 12px;
            background: linear-gradient(135deg, #7c9cff 0%, #c17cff 100%);
            display: grid; place-items: center; font-size: 22px;
            box-shadow: 0 8px 24px -8px rgba(124, 156, 255, 0.5);
        }
        .brand h1 { margin: 0; font-size: 1.4em; letter-spacing: -0.01em; }
        .brand .sub { color: var(--muted); font-size: 0.85em; margin-top: 2px; }

        .status-bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
        .pill {
            display: inline-flex; align-items: center; gap: 8px;
            padding: 7px 12px; border-radius: 999px;
            background: var(--panel); border: 1px solid var(--border);
            font-size: 0.82em; color: var(--text);
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
        }
        .pill .dot {
            width: 8px; height: 8px; border-radius: 50%; background: var(--success);
            box-shadow: 0 0 10px var(--success);
        }
        .pill .label { color: var(--muted); font-family: inherit; }
        .pill.clickable { cursor: pointer; transition: all 0.15s; }
        .pill.clickable:hover { background: var(--panel-2); border-color: var(--border-strong); }

        /* Sections */
        section { margin-top: 36px; }
        .section-head {
            display: flex; align-items: baseline; gap: 12px; margin-bottom: 14px;
        }
        .section-head h2 {
            margin: 0; font-size: 0.78em; font-weight: 700;
            color: var(--muted); text-transform: uppercase; letter-spacing: 0.12em;
        }
        .section-head .count { color: var(--border-strong); font-size: 0.78em; }

        /* Cards */
        .grid {
            display: grid; gap: 14px;
            grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
        }
        .card {
            position: relative;
            background: linear-gradient(180deg, var(--panel) 0%, var(--bg-2) 100%);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 18px;
            display: flex; flex-direction: column; gap: 14px;
            transition: transform 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
            overflow: hidden;
        }
        .card::before {
            content: ""; position: absolute; inset: 0; border-radius: 14px;
            background: linear-gradient(135deg, var(--svc-color, transparent) 0%, transparent 40%);
            opacity: 0.12; pointer-events: none;
        }
        .card:hover {
            transform: translateY(-2px);
            border-color: var(--border-strong);
            box-shadow: 0 12px 32px -12px rgba(0, 0, 0, 0.6);
        }
        .card-head { display: flex; align-items: center; gap: 12px; }
        .icon {
            width: 40px; height: 40px; border-radius: 10px;
            display: grid; place-items: center;
            font-size: 18px; font-weight: 700;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
            color: white;
            flex-shrink: 0;
        }
        .meta { min-width: 0; }
        .meta .name { font-weight: 600; font-size: 1.02em; }
        .meta .port {
            color: var(--muted); font-family: ui-monospace, monospace; font-size: 0.82em;
            margin-top: 2px;
        }
        .actions { display: flex; gap: 8px; }
        .btn {
            flex: 1; padding: 9px 12px; border-radius: 8px;
            border: 1px solid var(--border); background: var(--panel-2); color: var(--text);
            font-size: 0.88em; font-weight: 500; cursor: pointer;
            text-decoration: none; text-align: center;
            transition: all 0.12s;
            font-family: inherit;
        }
        .btn:hover { background: #262b3a; border-color: var(--border-strong); }
        .btn.primary {
            background: var(--accent); border-color: var(--accent); color: #0b0d12;
            font-weight: 600;
        }
        .btn.primary:hover { background: var(--accent-hover); border-color: var(--accent-hover); }

        /* Utility panel */
        .util {
            background: var(--panel); border: 1px solid var(--border);
            border-radius: 14px; padding: 18px;
        }
        .util .line { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin-bottom: 10px; }
        .util .line:last-child { margin-bottom: 0; }
        .util code {
            background: var(--bg-2); padding: 8px 12px; border-radius: 8px;
            font-size: 0.88em; border: 1px solid var(--border); flex: 1; min-width: 200px;
            font-family: ui-monospace, monospace;
        }
        .util .btn { flex: 0 0 auto; }
        .note { color: var(--muted); font-size: 0.82em; margin: 12px 0 0; }

        /* VPN states */
        .dot.off { background: #ef4444; box-shadow: 0 0 10px #ef4444; }
        .dot.connecting { background: var(--warn); box-shadow: 0 0 10px var(--warn); animation: pulse 1s infinite; }
        @keyframes pulse { 50% { opacity: 0.4; } }
        select.btn { background: var(--panel-2); color: var(--text); border: 1px solid var(--border); }

        /* Toast */
        #toast {
            position: fixed; bottom: 28px; left: 50%;
            transform: translateX(-50%) translateY(20px);
            background: var(--panel-2); border: 1px solid var(--border-strong);
            color: var(--text); padding: 11px 18px; border-radius: 10px;
            opacity: 0; transition: all 0.2s ease; pointer-events: none;
            font-size: 0.9em; box-shadow: 0 10px 30px -10px rgba(0,0,0,0.6);
        }
        #toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

        @media (max-width: 600px) {
            .wrap { padding: 24px 16px 60px; }
            header { flex-direction: column; align-items: flex-start; }
        }
    </style>
</head>
<body>
<div class="wrap">
    <header>
        <div class="brand">
            <div class="logo">🎮</div>
            <div>
                <h1>Steam Deck Portal</h1>
                <div class="sub">Self-hosted media &amp; automation</div>
            </div>
        </div>
        <div class="status-bar">
            <span class="pill" id="vpn-pill" title="Surfshark VPN status">
                <span class="dot" id="vpn-dot"></span>
                <span class="label">VPN</span>
                <span id="vpn-label">checking...</span>
            </span>
            <span class="pill" id="vpn-ip-pill" style="display:none" title="qBittorrent public IP">
                <span class="label">IP</span>
                <span id="vpn-ip">-</span>
            </span>
            <span class="pill clickable" onclick="toggleHost()" id="toggle-pill" title="Toggle between MagicDNS and Tailscale IP">
                <span class="label" id="toggle-key">DNS</span>
                <span id="host-label">$FULL_HOSTNAME</span>
            </span>
        </div>
    </header>

    <section>
        <div class="section-head"><h2>Media</h2><span class="count" id="media-count"></span></div>
        <div class="grid" id="media-grid"></div>
    </section>

    <section>
        <div class="section-head"><h2>*arr Stack</h2><span class="count" id="arr-count"></span></div>
        <div class="grid" id="arr-grid"></div>
    </section>

    <section>
        <div class="section-head"><h2>Downloads</h2><span class="count" id="dl-count"></span></div>
        <div class="grid" id="dl-grid"></div>
    </section>

    <section>
        <div class="section-head"><h2>Surfshark VPN</h2></div>
        <div class="util">
            <div class="line">
                <select id="vpn-country" class="btn" style="flex:0 0 auto; min-width:180px; appearance:auto;">
                    <option value="United States">United States</option>
                    <option value="United Kingdom">United Kingdom</option>
                    <option value="Canada">Canada</option>
                    <option value="Germany">Germany</option>
                    <option value="Netherlands">Netherlands</option>
                    <option value="Switzerland">Switzerland</option>
                    <option value="Sweden">Sweden</option>
                    <option value="France">France</option>
                    <option value="Japan">Japan</option>
                    <option value="Australia">Australia</option>
                    <option value="Brazil">Brazil</option>
                    <option value="Singapore">Singapore</option>
                </select>
                <button class="btn primary" onclick="switchVpn()">Switch Location</button>
                <button class="btn" onclick="verifyVpn()">Verify IP</button>
                <button class="btn" onclick="refreshVpn()">Refresh Status</button>
            </div>
            <p class="note" id="vpn-note">qBittorrent traffic is routed through this VPN. Kill switch is active.</p>
        </div>
    </section>

    <section>
        <div class="section-head"><h2>Shell</h2></div>
        <div class="util">
            <div class="line">
                <code id="ssh-cmd">ssh deck@$FULL_HOSTNAME</code>
                <button class="btn" onclick="copy(document.getElementById('ssh-cmd').textContent)">Copy</button>
            </div>
            <div class="line">
                <code id="ping-cmd">ping $FULL_HOSTNAME</code>
                <button class="btn" onclick="copy(document.getElementById('ping-cmd').textContent)">Copy</button>
            </div>
            <p class="note">SSH requires <code style="background:transparent;border:none;padding:0;">sshd</code> running on the Steam Deck.</p>
        </div>
    </section>
</div>

<div id="toast"></div>

<script>
    const HOST = "$FULL_HOSTNAME";
    const IP = "$TS_IP";
    let useIp = false;

    const services = {
        media: [
            { name: "Jellyfin",       port: 8096,  letter: "J", color: "#00a4dc" },
            { name: "Stremio Server", port: 11470, letter: "S", color: "#7b5bf5", note: "backend" },
        ],
        arr: [
            { name: "Sonarr",   port: 8989, letter: "S", color: "#3da5d9" },
            { name: "Radarr",   port: 7878, letter: "R", color: "#f5c518" },
            { name: "Prowlarr", port: 9696, letter: "P", color: "#e44c30" },
        ],
        dl: [
            { name: "qBittorrent", port: 8080, letter: "q", color: "#2f67b2" },
        ],
    };

    function host() { return useIp ? IP : HOST; }
    function url(s) { return "http://" + host() + ":" + s.port + (s.path || ""); }
    function esc(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":"&#39;"}[c])); }

    function render() {
        for (const [key, list] of Object.entries(services)) {
            const grid = document.getElementById(key + "-grid");
            document.getElementById(key + "-count").textContent = list.length;
            grid.innerHTML = list.map(s => \`
                <div class="card" style="--svc-color: \${s.color}">
                    <div class="card-head">
                        <div class="icon" style="background:\${s.color}">\${s.letter}</div>
                        <div class="meta">
                            <div class="name">\${esc(s.name)}</div>
                            <div class="port">:\${s.port}\${s.note ? " &middot; " + esc(s.note) : ""}</div>
                        </div>
                    </div>
                    <div class="actions">
                        <a class="btn primary" href="\${url(s)}" target="_blank" rel="noopener">Open</a>
                        <button class="btn" onclick="copy('\${url(s)}')">Copy URL</button>
                    </div>
                </div>
            \`).join("");
        }
        document.getElementById("host-label").textContent = host();
        document.getElementById("toggle-key").textContent = useIp ? "IP" : "DNS";
        document.getElementById("ssh-cmd").textContent = "ssh deck@" + host();
        document.getElementById("ping-cmd").textContent = "ping " + host();
    }

    function toggleHost() { useIp = !useIp; render(); }

    function copy(text) {
        const done = () => toast("Copied " + text);
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(done).catch(() => fallback(text, done));
        } else {
            fallback(text, done);
        }
    }

    function fallback(text, done) {
        const t = document.createElement("textarea");
        t.value = text; t.style.position = "fixed"; t.style.top = "-9999px";
        document.body.appendChild(t); t.focus(); t.select();
        try { document.execCommand("copy"); done(); } catch(e) { toast("Copy failed"); }
        document.body.removeChild(t);
    }

    let toastTimer;
    function toast(msg) {
        const el = document.getElementById("toast");
        el.textContent = msg; el.classList.add("show");
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => el.classList.remove("show"), 1600);
    }

    async function refreshVpn() {
        const dot = document.getElementById("vpn-dot");
        const label = document.getElementById("vpn-label");
        const ipPill = document.getElementById("vpn-ip-pill");
        const ipLabel = document.getElementById("vpn-ip");
        try {
            const res = await fetch("/api/v1/openvpn/status");
            const data = await res.json();
            const running = data.status === "running";
            dot.className = "dot" + (running ? "" : " off");
            label.textContent = running ? "Connected" : "Disconnected";

            if (running) {
                const ipRes = await fetch("/api/v1/publicip/ip");
                const ipData = await ipRes.json();
                ipPill.style.display = "";
                ipLabel.textContent = (ipData.country || "?") + " \u00b7 " + (ipData.public_ip || "?");
            } else {
                ipPill.style.display = "none";
            }
        } catch (e) {
            dot.className = "dot off";
            label.textContent = "Unreachable";
            ipPill.style.display = "none";
        }
    }

    async function switchVpn() {
        const country = document.getElementById("vpn-country").value;
        const dot = document.getElementById("vpn-dot");
        const label = document.getElementById("vpn-label");
        dot.className = "dot connecting";
        label.textContent = "Switching to " + country + "...";
        toast("Switching VPN to " + country + " (this takes ~30s)...");
        try {
            await fetch("/switch?country=" + encodeURIComponent(country));
            const poll = setInterval(async () => {
                try {
                    const r = await fetch("/api/v1/openvpn/status");
                    const d = await r.json();
                    if (d.status === "running") {
                        clearInterval(poll);
                        refreshVpn();
                        toast("VPN switched to " + country);
                    }
                } catch(e) {}
            }, 3000);
            setTimeout(() => clearInterval(poll), 120000);
        } catch (e) {
            toast("Failed to switch VPN");
            refreshVpn();
        }
    }

    async function verifyVpn() {
        toast("Checking qBittorrent's public IP...");
        try {
            const res = await fetch("/api/v1/publicip/ip");
            const data = await res.json();
            toast("VPN IP: " + data.public_ip + " (" + (data.country || "unknown") + ")");
        } catch (e) {
            toast("Could not verify - VPN may be down");
        }
    }

    render();
    refreshVpn();
    setInterval(refreshVpn, 30000);
</script>
</body>
</html>
EOF

# ===== Start portal =====
sudo podman run -d --name portal --replace --restart always \
  --network host \
  -v "$CONFIG_BASE/portal/www":/usr/share/nginx/html:Z \
  -v "$CONFIG_BASE/portal/nginx.conf":/etc/nginx/conf.d/default.conf:Z \
  docker.io/library/nginx:alpine

# ===== Start media stack (rootless) =====
podman run --pull=always -d --name jellyfin --replace --restart always \
  --network host \
  -v "$JELLYFIN_DIR":/config:Z \
  -v "$MEDIA_DIR/Downloads":/cache:Z \
  -v "$MEDIA_DIR":/media:Z \
  docker.io/jellyfin/jellyfin:latest

podman run --pull=always -d --name stremio-server --replace --restart always \
  -p 11470:11470 \
  -v "$STREMIO_DIR":/root/.stremio-server:Z \
  docker.io/stremio/server:latest

podman run --pull=always -d --name prowlarr --replace --restart always \
  --network host \
  -e PUID=1000 -e PGID=1000 \
  -v "$CONFIG_BASE/prowlarr":/config:Z \
  -v "$MEDIA_DIR":/media:Z \
  lscr.io/linuxserver/prowlarr:latest

podman run --pull=always -d --name sonarr --replace --restart always \
  --network host \
  -e PUID=1000 -e PGID=1000 \
  -v "$CONFIG_BASE/sonarr":/config:Z \
  -v "$MEDIA_DIR":/media:Z \
  lscr.io/linuxserver/sonarr:latest

podman run --pull=always -d --name radarr --replace --restart always \
  --network host \
  -e PUID=1000 -e PGID=1000 \
  -v "$CONFIG_BASE/radarr":/config:Z \
  -v "$MEDIA_DIR":/media:Z \
  lscr.io/linuxserver/radarr:latest

# ===== Start Gluetun (Surfshark VPN) =====
podman run --pull=always -d --name gluetun --replace --restart always \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -e VPN_SERVICE_PROVIDER=surfshark \
  -e VPN_TYPE=openvpn \
  -e OPENVPN_USER="$SURFSHARK_USER" \
  -e OPENVPN_PASSWORD="$SURFSHARK_PASS" \
  -e SERVER_COUNTRIES="United States" \
  -e FIREWALL_VPN_INPUT_PORTS=8080 \
  -e UPDATER_PERIOD=24h \
  -e DOT=off \
  -e DNS_ADDRESS=1.1.1.1 \
  -e HEALTH_TARGET_ADDRESS=1.1.1.1:443 \
  -p 8080:8080 \
  -p 8000:8000 \
  -v "$CONFIG_BASE/gluetun":/gluetun:Z \
  docker.io/qmcgaw/gluetun:latest

echo "Waiting for Gluetun VPN to connect..."
for i in {1..30}; do
    if podman exec gluetun wget -qO- http://127.0.0.1:8000/v1/openvpn/status 2>/dev/null | grep -q running; then
        echo "Gluetun VPN connected."
        break
    fi
    sleep 2
done

# Fix qBittorrent CSRF rejection for remote access
QB_CONF="$CONFIG_BASE/qbittorrent/qBittorrent/qBittorrent.conf"
if [ -f "$QB_CONF" ] && ! grep -q "WebUI.ServerDomains" "$QB_CONF"; then
    sed -i '/\[Preferences\]/a WebUI\\CSRFProtection=false\nWebUI\\ServerDomains=*' "$QB_CONF"
fi

# ===== Start qBittorrent (routed through Gluetun VPN) =====
podman run --pull=always -d --name qbittorrent --replace --restart always \
  --network container:gluetun \
  -e PUID=1000 -e PGID=1000 \
  -v "$CONFIG_BASE/qbittorrent":/config:Z \
  -v "$MEDIA_DIR":/media:Z \
  lscr.io/linuxserver/qbittorrent:latest

# ===== VPN switch script =====
cat > "$HOME/switch-vpn.sh" <<SWITCHEOF
#!/bin/bash
COUNTRY="\${1:-United States}"
podman stop qbittorrent gluetun 2>/dev/null
podman rm qbittorrent gluetun 2>/dev/null

podman run --pull=never -d --name gluetun --replace --restart always \\
  --cap-add NET_ADMIN --device /dev/net/tun \\
  -e VPN_SERVICE_PROVIDER=surfshark -e VPN_TYPE=openvpn \\
  -e OPENVPN_USER="$SURFSHARK_USER" -e OPENVPN_PASSWORD="$SURFSHARK_PASS" \\
  -e SERVER_COUNTRIES="\$COUNTRY" \\
  -e FIREWALL_VPN_INPUT_PORTS=8080 -e UPDATER_PERIOD=24h \\
  -e DOT=off -e DNS_ADDRESS=1.1.1.1 -e HEALTH_TARGET_ADDRESS=1.1.1.1:443 \\
  -p 8080:8080 -p 8000:8000 \\
  -v "$CONFIG_BASE/gluetun":/gluetun:Z \\
  docker.io/qmcgaw/gluetun:latest

for i in {1..30}; do
    if podman exec gluetun wget -qO- http://127.0.0.1:8000/v1/openvpn/status 2>/dev/null | grep -q running; then
        break
    fi
    sleep 2
done

podman run --pull=never -d --name qbittorrent --replace --restart always \\
  --network container:gluetun \\
  -e PUID=1000 -e PGID=1000 \\
  -v "$CONFIG_BASE/qbittorrent":/config:Z \\
  -v "$MEDIA_DIR":/media:Z \\
  lscr.io/linuxserver/qbittorrent:latest
SWITCHEOF
chmod +x "$HOME/switch-vpn.sh"

# ===== VPN switch helper server =====
cat > "$HOME/vpn-switch-server.py" <<'PYEOF'
import subprocess, json, os, signal
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

SETUP = os.path.expanduser("~/server_setup.sh")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        params = parse_qs(urlparse(self.path).query)
        country = params.get("country", ["United States"])[0]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "switching", "country": country}).encode())
        self.wfile.flush()
        subprocess.Popen(["bash", os.path.expanduser("~/switch-vpn.sh"), country])
    def log_message(self, *a): pass

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 9090), Handler).serve_forever()
PYEOF

# Kill old switch server and start new one
pkill -f vpn-switch-server.py 2>/dev/null || true
nohup python3 "$HOME/vpn-switch-server.py" > /dev/null 2>&1 &

echo "========================================================"
echo " PORTAL: http://localhost"
echo " TAILSCAPE (MagicDNS): http://$FULL_HOSTNAME"
echo "========================================================"
echo "IMPORTANT: Make sure SSH server is running on Steam Deck for Termius."
echo "You can enable it with: sudo systemctl enable sshd && sudo systemctl start sshd"
