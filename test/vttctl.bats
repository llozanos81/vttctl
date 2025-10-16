# Bats test suite for vttctl.sh

# To run: bats test/vttctl.bats

@test "validate command succeeds" {
  run ./vttctl.sh validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validating requirements"* ]]
}

@test "help command shows improved help text" {
  run ./vttctl.sh help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "vttctl.sh - FoundryVTT Docker Orchestration Utility" ]]
  [[ "$output" =~ "CORE COMMANDS:" ]]
  [[ "$output" =~ "MANAGEMENT COMMANDS:" ]]
  [[ "$output" =~ "MONITORING & DIAGNOSTICS:" ]]
  [[ "$output" =~ "DEVELOPMENT & UTILITIES:" ]]
  [[ "$output" =~ "For detailed documentation, see README.md" ]]
}

@test "unknown command prints error" {
  run ./vttctl.sh doesnotexist
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "default command runs without error" {
  # Skip test if expect is not installed
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh default
    expect "Version to set as default?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 127 ]
  [[ "$output" == *"Canceled."* ]] || [[ "$output" == *"Cleaning cancelled."* ]]
}

@test "default command cancels interactively" {
  # Skip test if expect is not installed
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh default
    expect "Version to set as default?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 127 ]
  [[ "$output" == *"Canceled."* ]] || [[ "$output" == *"Cleaning cancelled."* ]]
}

# Add more tests for backup, restore, build, etc. as needed.

@test "backup command fails if not in tmux/screen" {
  run ./vttctl.sh backup
  [ "$status" -ne 0 ]
  [[ "$output" == *"Backups must be run inside tmux or screen"* ]]
}

@test "build command lists available versions" {
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh build
    expect "Version to build?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Canceled" ]]
}

@test "restore command fails without backups" {
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh restore
    expect "Do you want to continue? (y/n):"
    send "y\r"
    expect "Version and date to restore?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Canceled" ]]
}

# Integration tests
@test "integration: validate and help commands" {
  run bash -c './vttctl.sh validate && ./vttctl.sh help'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Validating requirements" ]]
  [[ "$output" =~ "CORE COMMANDS:" ]]
}

# Template tests
@test "Dockerfile template renders correctly for v9" {
  run python3 python/template_renderer.py --template templates/Dockerfile.j2 --output /tmp/test_dockerfile_v9 --var major_version=9 --var nodejs_version=16.5.x --var alpine_version=3.16
  [ "$status" -eq 0 ]
  run grep "FROM alpine:3.16" /tmp/test_dockerfile_v9
  [ "$status" -eq 0 ]
}

@test "Dockerfile template renders correctly for v11" {
  run python3 python/template_renderer.py --template templates/Dockerfile.j2 --output /tmp/test_dockerfile_v11 --var major_version=11 --var nodejs_version=18.x.x --var alpine_version=3.18
  [ "$status" -eq 0 ]
  run grep "FROM alpine:3.18" /tmp/test_dockerfile_v11
  [ "$status" -eq 0 ]
}

@test "Dockerfile template renders correctly for v13" {
  run python3 python/template_renderer.py --template templates/Dockerfile.j2 --output /tmp/test_dockerfile_v13 --var major_version=13 --var nodejs_version=22.x.x --var alpine_version=3.22
  [ "$status" -eq 0 ]
  run grep "FROM alpine:3.22" /tmp/test_dockerfile_v13
  [ "$status" -eq 0 ]
}

@test "backup index template renders correctly for v9" {
  run python3 python/template_renderer.py --template templates/backup_index.j2 --output /tmp/test_backup_v9.html --var major_version=9 --var backup_refresh=300000 --var backup_file_table="<tr><td>test</td></tr>" --var vttctl_version=1.0
  [ "$status" -eq 0 ]
  run grep "style.css" /tmp/test_backup_v9.html
  [ "$status" -eq 0 ]
  run grep "foundry2.css" /tmp/test_backup_v9.html
  [ "$status" -ne 0 ]
}

@test "backup index template renders correctly for v11" {
  run python3 python/template_renderer.py --template templates/backup_index.j2 --output /tmp/test_backup_v11.html --var major_version=11 --var backup_refresh=300000 --var backup_file_table="<tr><td>test</td></tr>" --var vttctl_version=1.0
  [ "$status" -eq 0 ]
  run grep "foundry2.css" /tmp/test_backup_v11.html
  [ "$status" -eq 0 ]
  run grep 'footer class="watermark"' /tmp/test_backup_v11.html
  [ "$status" -eq 0 ]
}

@test "backup index template renders correctly for v13" {
  run python3 python/template_renderer.py --template templates/backup_index.j2 --output /tmp/test_backup_v13.html --var major_version=13 --var backup_refresh=300000 --var backup_file_table="<tr><td>test</td></tr>" --var vttctl_version=1.0
  [ "$status" -eq 0 ]
  run grep "foundry2.css" /tmp/test_backup_v13.html
  [ "$status" -eq 0 ]
  run grep 'footer id="watermark"' /tmp/test_backup_v13.html
  [ "$status" -eq 0 ]
  run grep "main-background" /tmp/test_backup_v13.html
  [ "$status" -eq 0 ]
}

@test "rebuild_metadata generates correct backup index for v9" {
  # Create a test backup file
  mkdir -p backups/FoundryVTT
  touch backups/FoundryVTT/foundry_userdata_9.123-20251016.tar
  run expect -c '
    spawn bash -c "source src/workflow_backup.sh && rebuild_metadata backups/FoundryVTT/ http localhost /home/ubuntu/sites/legendaryrealms.com.mx 9 300000 1.0 false"
    expect eof
  '
  [ "$status" -eq 0 ]
  # Check if index.html contains style.css
  run grep "style.css" backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
  # Check no foundry2.css
  run grep "foundry2.css" backups/FoundryVTT/index.html
  [ "$status" -ne 0 ]
}

@test "rebuild_metadata generates correct backup index for v11" {
  run expect -c '
    spawn bash -c "source src/workflow_backup.sh && rebuild_metadata backups/FoundryVTT/ http localhost /home/ubuntu/sites/legendaryrealms.com.mx 11 300000 1.0 false"
    expect eof
  '
  [ "$status" -eq 0 ]
  # Check if index.html contains foundry2.css
  run grep "foundry2.css" backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
  # Check footer class watermark
  run grep 'footer class="watermark"' backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
}

@test "rebuild_metadata generates correct backup index for v13" {
  run expect -c '
    spawn bash -c "source src/workflow_backup.sh && rebuild_metadata backups/FoundryVTT/ http localhost /home/ubuntu/sites/legendaryrealms.com.mx 13 300000 1.0 false"
    expect eof
  '
  [ "$status" -eq 0 ]
  # Check if index.html contains foundry2.css
  run grep "foundry2.css" backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
  # Check footer id watermark
  run grep 'footer id="watermark"' backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
  # Check main-background
  run grep "main-background" backups/FoundryVTT/index.html
  [ "$status" -eq 0 ]
}

@test "wizard command runs interactively" {
  # Skip test if expect is not installed
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh wizard
    expect "vttctl Configuration Wizard"
    expect "Nginx production port"
    send "\r"
    expect "Nginx development port"
    send "\r"
    expect "Public production port"
    send "\r"
    expect "Enable SSL/HTTPS?"
    send "\r"
    expect "Hostname prefix for FQDN"
    send "\r"
    expect "Domain name"
    send "\r"
    expect "Default FoundryVTT version"
    send "\r"
    expect "Timezone"
    send "\r"
    expect "FoundryVTT user ID"
    send "\r"
    expect "FoundryVTT group ID"
    send "\r"
    expect "Enable development environment?"
    send "\r"
    expect "Save this configuration?"
    send "n\r"
    expect eof
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuration not saved."* ]]
}
