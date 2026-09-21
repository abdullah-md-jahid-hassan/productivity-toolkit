sudo apt update
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

sudo apt update
sudo apt install -y caddy




cat << 'EOF'
.
.
.
.
Run: sudo nano /etc/caddy/Caddyfile

Then list the record. Example:

sub.domain.com {
    reverse_proxy localhost:8000
}

Then Reload: sudo systemctl reload caddy
Then Check: sudo systemctl status caddy
EOF