1. **Samsung Happ**
- Enable LAN Connections
- IP: 192.168.1.128
- Port SOCSK-5 10808
- Port HTTP 10809
2. **Ubuntu**
- Settings/Network/Network Proxy
- Socks Host 192.168.1.128 10808
- HTTP Proxy 192.168.1.128 10809 - no actually needed
3. **Ubuntu Console**
- export https_proxy=http://192.168.1.128:10808
- export http_proxy=http://192.168.1.128:10808
- export all_proxy=http://192.168.1.128:10808 - no need?
- export all_proxy=socks5://192.168.1.128:10808 - no need?
4. **Run VS Code from console**
- code
