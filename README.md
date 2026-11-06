# 🍿 Streaming Starter Kit

> **Two projects, one goal:** Get movie & TV show streaming working on your Roku device with a beautiful interface and powerful backend.

---

## 📋 What's Included?

| Project | What It Does | Who It's For |
|---------|--------------|--------------|
| **🖥️ Server** (TMDB Embed API) | Finds streaming links from 13+ sources using TMDB (The Movie Database) | Runs on your computer, NAS, or server |
| **📺 RokuApp** | A Roku channel that plays streams from your Server | Installs on your Roku TV/device |

---

## 🎯 Quick Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Your Roku TV   │◄───►│  RokuApp        │◄───►│  Server         │
│  (Living Room)  │     │  (Channel)      │     │  (Your Computer)│
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              ▲                       ▲
                              │                       │
                              │              ┌─────────────────┐
                              └──────────────►│  TMDB + 13      │
                                              │  Streaming      │
                                              │  Providers      │
                                              └─────────────────┘
```

**In plain English:** You run the Server on a computer that's always on. The RokuApp on your TV talks to that Server to find and play movies/shows.

---

## 🚀 Get Started in 5 Minutes

### Prerequisites (One-time Setup)

| What You Need | Details |
|---------------|---------|
| **A computer** | Windows, Mac, or Linux (can be a Raspberry Pi, NAS, old laptop) |
| **Node.js 18+** | [Download here](https://nodejs.org/) — pick "LTS" version |
| **TMDB API Key** | Free at [themoviedb.org](https://www.themoviedb.org/settings/api) — click "Create" → "Developer" |
| **Roku Device** | Any Roku TV, Stick, or Box (developer mode enabled) |
| **Same Network** | Computer and Roku must be on the same Wi-Fi/LAN |

---

### Step 1: Set Up the Server

```bash
# 1. Open terminal/command prompt in the Server folder
cd Server

# 2. Install dependencies (run once)
npm install

# 3. Create your configuration file
cp .env.example .env   # (or create .env manually - see below)

# 4. Edit .env and add your TMDB API key
#    TMDB_API_KEY=your_key_here

# 5. Start the server
npm start
```

**You'll see:** `Server running on http://0.0.0.0:8787`

> ✅ **Test it:** Open `http://localhost:8787/` in your browser — you should see a login page.
> **Default login:** `admin` / `change-me` — **change this immediately!** or leave it, should be fine!

---

### Step 2: Configure Your Server (Web UI)

1. Open `http://YOUR_COMPUTER_IP:8787/` in a browser (use your computer's actual IP, not localhost)
2. Login with `admin` / `change-me`
3. **Immediately change your password** in the dashboard
4. Go to **Keys** panel → add your TMDB API key(s)
5. Go to **Core** panel → set your default providers (e.g., `4khdhub`, `vixsrc`)
6. Click **Save** in each panel

> 💡 **Finding your computer's IP:**
> - **Windows:** `ipconfig` → look for "IPv4 Address"
> - **Mac/Linux:** `ifconfig` or `ip a` → look for `inet` (usually 192.168.x.x or 10.x.x.x)

---

### Step 3: Install the Roku App

#### Option A: Sideload via Web (Easiest)

1. On your computer, zip the **entire `RokuApp` folder** (not the contents — the folder itself)
   - **Windows:** Right-click `RokuApp` → "Send to" → "Compressed (zipped) folder"
   - **Mac:** Right-click `RokuApp` → "Compress RokuApp"
   - **Linux:** `zip -r RokuApp.zip RokuApp`

2. On your Roku, enable **Developer Settings**:
   - Home → Settings → System → Advanced system settings → Developer settings
   - Enable "Developer mode" and note the **IP address** and **password** shown

3. In your browser, go to `http://YOUR_ROKU_IP/`
   - Login with username `rokudev` and the password from step 2
   - Click "Upload" → select your `RokuApp.zip`
   - Click "Install"

#### Option B: Command Line (For Developers)

```bash
# Install roku-deploy globally (one time)
npm install -g roku-deploy

# Deploy from the RokuApp folder
cd RokuApp
roku-deploy --host YOUR_ROKU_IP --password YOUR_ROKU_PASSWORD
```

---

### Step 4: Connect Roku App to Your Server

1. Launch the **"stub"** channel on your Roku
2. You'll see a settings in the left menu go to  **Server Address**
3. Enter: `http://YOUR_COMPUTER_IP:8787`
   - Example: `http://192.168.1.50:8787`
4. Save and start browsing!

---

## 🔧 Configuration Deep Dive

### Server `.env` File Explained

Create a file named `.env` in the `Server` folder with these options:

```bash
# REQUIRED: Get this free from https://www.themoviedb.org/settings/api
TMDB_API_KEY=your_single_key_here

# OR use multiple keys for rotation (recommended for heavy use)
# TMDB_API_KEYS=["key1","key2","key3"]

# OPTIONAL: Server port (default 8787)
# API_PORT=8787

# OPTIONAL: Which network interface to bind (default all)
# BIND_HOST=0.0.0.0

# OPTIONAL: Default streaming providers (comma-separated)
# DEFAULT_PROVIDERS=4khdhub,vixsrc,videasy

# OPTIONAL: Enable stream proxy (rewrites URLs through your server)
# ENABLE_PROXY=true 
# roku will probably only work with proxy on!

# OPTIONAL: FebBox/Showbox cookies (needed for Showbox provider)
# FEBBOX_COOKIES=your_jwt_cookie_here
```

> **Tip:** After first login, most settings can be changed in the web UI at `http://YOUR_IP:8787/config.html` — no need to edit `.env` again!

---

### Server Web UI Panels

| Panel | What You Can Do |
|-------|-----------------|
| **Core** | Change port, default providers, region |
| **Quality / Filters** | Set minimum quality (720p, 1080p, 4K), block codecs (Dolby Vision, HDR) |
| **Keys** | Add/remove TMDB API keys, add FebBox cookies |
| **Advanced** | Toggle providers on/off, enable/disable cache, proxy |
| **Server Status** | Run health checks on all providers, see live metrics |
| **Live Config** | View the exact merged configuration |

---

## 🐳 Run with Docker (Alternative)

If you prefer Docker over direct Node.js:

```bash
# Quick test (no config persistence)
docker run -it -p 8787:8787 inside4ndroid/tmdb-embed-api:latest

# Production (with your config persisted)
docker run --name tmdb-embed-api -p 8787:8787 \
  -e TMDB_API_KEY=YOUR_KEY \
  -v $(pwd)/utils/user-config.json:/app/utils/user-config.json \
  -v $(pwd)/utils/auth-users.json:/app/utils/auth-users.json \
  inside4ndroid/tmdb-embed-api:latest

# Or use docker-compose (included)
docker compose up -d --build
```

---

## 📱 Using the Roku App

Once connected, you'll see:

- **Movies** — Browse popular, top-rated, now playing
- **TV Shows** — Browse popular, airing today, top-rated
- **Search** — Find any title by name
- **Categories** — Filter by genre, year, rating

**Navigation:**
- **OK/Select** — Play or open details
- **Back** — Go back / exit
- **Options (*)** — Show stream sources, quality options
- **Left/Right** — Navigate lists

---

## 🛠 Troubleshooting

### "Can't connect to server" on Roku
- ✅ Check both devices are on same network
- ✅ Verify computer IP hasn't changed (set static IP/DHCP reservation)
- ✅ Try `http://COMPUTER_IP:8787/api/health` in browser — should return JSON
- ✅ Check firewall: allow port 8787 on your computer

### "No streams found" for a movie/show
- ✅ Add more TMDB keys in the Keys panel (rotation helps with rate limits)
- ✅ Enable more providers in Advanced panel
- ✅ Check Server Status → "Run Provider Functional Checks"
- ✅ Some titles genuinely have no sources — try a popular movie first

### Roku app shows "Channel install failed"
- ✅ Make sure you zipped the **RokuApp folder**, not its contents
- ✅ Roku must be in Developer Mode
- ✅ Try rebooting Roku: Settings → System → System restart

### Server won't start / port in use
```bash
# Find what's using port 8787
lsof -i :8787   # Mac/Linux
netstat -ano | findstr :8787   # Windows

# Kill it or change API_PORT in .env
```

---

## 🔒 Security Notes

| Concern | Mitigation |
|---------|------------|
| **Default password** | Change immediately on first login! |
| **Exposed on internet** | Don't port-forward 8787. Use Tailscale/VPN for remote access. |
| **TMDB keys** | Keep them secret — don't commit `.env` to Git |
| **Session cookies** | HttpOnly, 12-hour expiry, auto-logout on browser close |

---

## 📂 Project Structure

```
streaming-starter-kit/
├── Server/                    # Backend API (Node.js)
│   ├── apiServer.js          # Main server entry point
│   ├── providers/            # 13 streaming source plugins
│   ├── utils/
│   │   ├── user-config.json  # Your saved settings (auto-created)
│   │   └── auth-users.json   # Login credentials (auto-created)
│   ├── public/               # Admin UI (HTML/JS/CSS)
│   ├── .env                  # YOUR CONFIG (create this!)
│   ├── docker-compose.yml    # Docker deployment
│   └── package.json          # Dependencies
│
└── RokuApp/                  # Roku Channel (BrightScript)
    ├── manifest              # App metadata (title, version, icons)
    ├── source/               # BrightScript source code
    │   ├── main.brs          # Entry point
    │   ├── api.brs           # Server communication
    │   ├── navigation.brs    # UI navigation
    │   ├── config.brs        # Settings storage
    │   └── cache.brs         # Local caching
    ├── components/           # Reusable UI components
    ├── images/               # Icons, splash screens
    └── fonts/                # Custom fonts
```

---

## 🤝 Contributing

Found a bug? Want a new provider? PRs welcome!

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a PR with a clear description

**For new providers:** Add a file in `Server/providers/` and register it in `Server/providers/registry.js`.

---

## 📜 License

MIT License — use freely, modify, share. See `Server/LICENSE.md` for details.

---

## 🙏 Acknowledgements

- **TMDB** for the amazing free movie/TV database
- **Streaming providers** (Showbox, 4KHDHub, VixSrc, Videasy, Vidlink, DahmerMovies, StreamFlix, VaPlayer, CastleTV, HDGharTV, NetMirror, OneTouchTV, ZXCStreams)
- **Roku** for the developer platform
- **Open source community** for inspiration and code

---

## 💬 Need Help?

- **Issues:** [GitHub Issues](https://github.com/your-repo/issues)
- **Discussions:** [GitHub Discussions](https://github.com/your-repo/discussions)
- **Server logs:** Check terminal where you ran `npm start`
- **Roku logs:** `roku-deploy --host IP --password PWD --log`

---

> **Happy Streaming!** 🍿✨
> 
> *Built with ❤️ for the home theater enthusiast community*
