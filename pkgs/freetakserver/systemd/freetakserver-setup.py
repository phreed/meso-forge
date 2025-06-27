#!/usr/bin/env python3
"""
FreeTAKServer Service Setup Script
This script sets up the FreeTAKServer service for systemd management.
"""

import os
import sys
import pwd
import grp
import stat
import subprocess
import argparse
from pathlib import Path
from typing import Optional


class FreeTAKServerSetup:
    """FreeTAKServer systemd service setup utility."""

    def __init__(self):
        self.service_name = "freetakserver"
        self.service_user = "freetakserver"
        self.service_group = "freetakserver"
        self.service_home = Path("/var/lib/freetakserver")
        self.config_dir = Path("/etc/freetakserver")
        self.log_dir = Path("/var/log/freetakserver")

    def check_root(self) -> None:
        """Check if running as root."""
        if os.geteuid() != 0:
            print("❌ Error: This script must be run as root (use sudo)")
            sys.exit(1)

    def group_exists(self, group_name: str) -> bool:
        """Check if a group exists."""
        try:
            grp.getgrnam(group_name)
            return True
        except KeyError:
            return False

    def user_exists(self, username: str) -> bool:
        """Check if a user exists."""
        try:
            pwd.getpwnam(username)
            return True
        except KeyError:
            return False

    def run_command(self, cmd: list, check: bool = True) -> subprocess.CompletedProcess:
        """Run a system command."""
        try:
            return subprocess.run(cmd, check=check, capture_output=True, text=True)
        except subprocess.CalledProcessError as ex:
            print(f"❌ Command failed: {' '.join(cmd)}")
            print(f"   Error: {ex.stderr}")
            if check:
                sys.exit(1)
            # Transform CalledProcessError into CompletedProcess
            return subprocess.CompletedProcess(
                args=ex.cmd,
                returncode=ex.returncode,
                stdout=ex.stdout,
                stderr=ex.stderr
            )

    def create_system_user(self) -> None:
        """Create system user and group if they don't exist."""
        print("👥 Setting up system user and group...")

        # Create group
        if not self.group_exists(self.service_group):
            print(f"Creating group: {self.service_group}")
            self.run_command(["groupadd", "--system", self.service_group])
        else:
            print(f"✓ Group {self.service_group} already exists")

        # Create user
        if not self.user_exists(self.service_user):
            print(f"Creating user: {self.service_user}")
            self.run_command([
                "useradd", "--system",
                "--gid", self.service_group,
                "--home-dir", str(self.service_home),
                "--shell", "/bin/false",
                "--comment", "FreeTAKServer service user",
                self.service_user
            ])
        else:
            print(f"✓ User {self.service_user} already exists")

    def create_directories(self) -> None:
        """Create required directories with proper permissions."""
        print("📁 Creating directories...")

        directories = [
            (self.service_home, 0o755),
            (self.service_home / "certs", 0o700),
            (self.service_home / "data", 0o755),
            (self.config_dir, 0o755),
            (self.log_dir, 0o755),
        ]

        # Get user and group IDs
        try:
            user_info = pwd.getpwnam(self.service_user)
            group_info = grp.getgrnam(self.service_group)
            uid, gid = user_info.pw_uid, group_info.gr_gid
        except KeyError as e:
            print(f"❌ Error: Could not find user/group: {e}")
            sys.exit(1)

        for directory, mode in directories:
            directory.mkdir(parents=True, exist_ok=True)

            # Set ownership
            if directory == self.config_dir:
                # Config directory should be owned by root
                os.chown(directory, 0, 0)
            else:
                os.chown(directory, uid, gid)

            # Set permissions
            directory.chmod(mode)
            print(f"✓ {directory} (mode: {oct(mode)})")

    def create_config_file(self) -> None:
        """Create basic configuration file if it doesn't exist."""
        config_file = self.config_dir / "config.yaml"

        if config_file.exists():
            print(f"✓ Configuration file already exists: {config_file}")
            return

        print(f"📝 Creating basic configuration file: {config_file}")

        config_content = '''# FreeTAKServer Configuration
# For full configuration options, see: https://freetakteam.github.io/FreeTAKServer-User-Docs/

system:
  # Database configuration
  database:
    type: sqlite
    path: /var/lib/freetakserver/data/fts.db

  # Logging configuration
  logging:
    level: INFO
    file: /var/log/freetakserver/fts.log

  # Certificate configuration
  certificates:
    cert_path: /var/lib/freetakserver/certs
    ca_cert: ca.crt
    server_cert: server.crt
    server_key: server.key

network:
  # TCP API port (CoT)
  tcp_port: 8087

  # SSL API port (CoT SSL)
  ssl_port: 8089

  # HTTP API port
  http_port: 8080

  # HTTPS API port
  https_port: 8443

  # Federation port
  federation_port: 9000

security:
  # Enable SSL/TLS
  ssl_enabled: true

  # Authentication settings
  authentication:
    enabled: false
    method: password

ui:
  # Web UI settings
  enabled: true
  port: 5000
  host: 0.0.0.0
'''

        with open(config_file, 'w') as f:
            f.write(config_content)

        # Set permissions (root owned, readable by all)
        os.chown(config_file, 0, 0)
        config_file.chmod(0o644)

    def create_environment_file(self) -> None:
        """Create environment file for the service."""
        env_file = Path("/etc/default/freetakserver")

        if env_file.exists():
            print(f"✓ Environment file already exists: {env_file}")
            return

        print(f"📝 Creating environment file: {env_file}")

        env_content = '''# FreeTAKServer Environment Variables

# Set to false after first successful start
FTS_FIRST_START=true

# Python optimization
PYTHONUNBUFFERED=1
PYTHONOPTIMIZE=1

# Configuration file path
FTS_CONFIG_FILE=/etc/freetakserver/config.yaml

# Data directory
FTS_DATA_DIR=/var/lib/freetakserver/data

# Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
FTS_LOG_LEVEL=INFO
'''

        with open(env_file, 'w') as f:
            f.write(env_content)

        # Set permissions (root owned, readable by all)
        os.chown(env_file, 0, 0)
        env_file.chmod(0o644)

    def create_logrotate_config(self) -> None:
        """Create log rotation configuration."""
        logrotate_file = Path("/etc/logrotate.d/freetakserver")

        if logrotate_file.exists():
            print(f"✓ Log rotation config already exists: {logrotate_file}")
            return

        print(f"📝 Creating log rotation configuration: {logrotate_file}")

        logrotate_content = '''/var/log/freetakserver/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 freetakserver freetakserver
    postrotate
        systemctl reload freetakserver || true
    endscript
}
'''

        with open(logrotate_file, 'w') as f:
            f.write(logrotate_content)

        # Set permissions (root owned, readable by all)
        os.chown(logrotate_file, 0, 0)
        logrotate_file.chmod(0o644)

    def setup_systemd_service(self) -> None:
        """Configure systemd service."""
        print("⚙️  Configuring systemd service...")

        # Find the systemd unit file in the conda package
        import sys
        import site

        # Try to find the unit file in conda installation
        conda_systemd_file = None
        possible_locations = [
            # Standard conda locations
            Path(sys.prefix) / "lib" / "systemd" / "system" / f"{self.service_name}.service",
            # Site packages location (fallback)
            Path(site.getsitepackages()[0]).parent / "lib" / "systemd" / "system" / f"{self.service_name}.service",
        ]

        for location in possible_locations:
            if location.exists():
                conda_systemd_file = location
                break

        if not conda_systemd_file:
            print(f"❌ Error: Could not find {self.service_name}.service unit file in conda package")
            print("   Expected locations:")
            for loc in possible_locations:
                print(f"     {loc}")
            sys.exit(1)

        # Copy the unit file to system location
        system_systemd_dir = Path("/etc/systemd/system")
        system_unit_file = system_systemd_dir / f"{self.service_name}.service"

        print(f"Copying systemd unit file from {conda_systemd_file} to {system_unit_file}")

        # Ensure system directory exists
        system_systemd_dir.mkdir(parents=True, exist_ok=True)

        # Copy the file
        import shutil
        shutil.copy2(conda_systemd_file, system_unit_file)

        # Set proper permissions (root owned, readable by all)
        os.chown(system_unit_file, 0, 0)
        system_unit_file.chmod(0o644)

        print(f"✓ Unit file installed to {system_unit_file}")

        # Reload systemd daemon
        print("Reloading systemd daemon...")
        self.run_command(["systemctl", "daemon-reload"])

        # Enable the service (but don't start it automatically)
        print(f"Enabling {self.service_name} service...")
        self.run_command(["systemctl", "enable", self.service_name])

        # Verify the service is properly configured
        self.verify_systemd_service()

    def verify_systemd_service(self) -> None:
        """Verify that the systemd service is properly configured."""
        print("🔍 Verifying systemd service configuration...")

        # Check if service unit file exists in system location
        system_unit_file = Path("/etc/systemd/system") / f"{self.service_name}.service"
        if not system_unit_file.exists():
            print(f"❌ Error: Unit file not found at {system_unit_file}")
            sys.exit(1)

        # Check if systemctl can find the service
        result = self.run_command(["systemctl", "status", self.service_name], check=False)
        if "could not be found" in result.stderr.lower():
            print(f"❌ Error: systemctl cannot find service '{self.service_name}'")
            sys.exit(1)

        # Check if service is enabled
        result = self.run_command(["systemctl", "is-enabled", self.service_name], check=False)
        if result.returncode == 0 and result.stdout.strip() == "enabled":
            print(f"✓ Service {self.service_name} is enabled")
        else:
            print(f"⚠️  Warning: Service {self.service_name} may not be properly enabled")

        print("✓ Systemd service verification completed")

    def print_completion_message(self) -> None:
        """Print setup completion message with instructions."""
        print()
        print("🎉 FreeTAKServer service setup completed successfully!")
        print()
        print("📁 Setup Summary:")
        print(f"   Configuration file: {self.config_dir}/config.yaml")
        print(f"   Environment file: /etc/default/freetakserver")
        print(f"   Systemd unit file: /etc/systemd/system/{self.service_name}.service")
        print(f"   Service home directory: {self.service_home}")
        print(f"   Log directory: {self.log_dir}")
        print()
        print("⚠️  IMPORTANT: Before starting the service, you should:")
        print(f"   1. Review and customize {self.config_dir}/config.yaml")
        print(f"   2. Generate SSL certificates in {self.service_home}/certs/")
        print("   3. Set FTS_FIRST_START=false in /etc/default/freetakserver after first run")
        print()
        print("🔑 To generate self-signed certificates:")
        print(f"   sudo -u {self.service_user} openssl req -x509 -newkey rsa:4096 \\")
        print(f"     -keyout {self.service_home}/certs/server.key \\")
        print(f"     -out {self.service_home}/certs/server.crt \\")
        print("     -days 365 -nodes")
        print()
        print("🚀 Service Management Commands:")
        print(f"   Start service:    sudo systemctl start {self.service_name}")
        print(f"   Stop service:     sudo systemctl stop {self.service_name}")
        print(f"   Restart service:  sudo systemctl restart {self.service_name}")
        print(f"   Check status:     sudo systemctl status {self.service_name}")
        print(f"   View logs:        sudo journalctl -u {self.service_name} -f")
        print()
        print("🌐 Default Network Ports:")
        print("   TCP CoT:     8087")
        print("   SSL CoT:     8089")
        print("   HTTP API:    8080")
        print("   HTTPS API:   8443")
        print("   Federation:  9000")
        print("   Web UI:      5000")
        print()
        print("📖 For more information, visit:")
        print("   https://freetakteam.github.io/FreeTAKServer-User-Docs/")

    def setup(self, force: bool = False) -> None:
        """Run the complete setup process."""
        print("🔧 Setting up FreeTAKServer service...")
        print()

        try:
            self.check_root()
            self.create_system_user()
            self.create_directories()
            self.create_config_file()
            self.create_environment_file()
            self.create_logrotate_config()
            self.setup_systemd_service()
            self.print_completion_message()

        except KeyboardInterrupt:
            print("\n❌ Setup interrupted by user")
            sys.exit(1)
        except Exception as e:
            print(f"\n❌ Setup failed with error: {e}")
            sys.exit(1)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="FreeTAKServer systemd service setup utility",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo freetakserver-setup        # Run complete setup
  sudo freetakserver-setup --help # Show this help message

This script must be run as root (use sudo).
        """
    )

    parser.add_argument(
        "--force",
        action="store_true",
        help="Force overwrite existing configuration files"
    )

    parser.add_argument(
        "--version",
        action="version",
        version="FreeTAKServer Setup 1.0.0"
    )

    args = parser.parse_args()

    setup = FreeTAKServerSetup()
    setup.setup(force=args.force)


if __name__ == "__main__":
    main()
