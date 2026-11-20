{
  description = "A Nix-flake-based Python development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
      scanSecrets = pkgs: pkgs.writeShellApplication {
        name = "scan-secrets";
        runtimeInputs = [ pkgs.git pkgs.ripsecrets pkgs.trufflehog ];
        text = ''
          scan_paths=(.)

          if [[ "''${1:-}" == "--staged" ]]; then
            git rev-parse --show-toplevel >/dev/null 2>&1 || {
              echo "scan-secrets --staged must be run inside a Git repository" >&2
              exit 2
            }
            mapfile -d "" -t scan_paths < <(
              git diff --cached --name-only --diff-filter=ACMRT -z
            )
            if (( ''${#scan_paths[@]} == 0 )); then
              echo "No staged files to scan."
              exit 0
            fi
            for index in "''${!scan_paths[@]}"; do
              scan_paths[index]="./''${scan_paths[index]}"
            done
          elif (( $# > 0 )); then
            echo "Usage: scan-secrets [--staged]" >&2
            exit 2
          fi

          status=0
          echo "Running ripsecrets..."
          ripsecrets --strict-ignore "''${scan_paths[@]}" || status=$?

          echo "Running trufflehog..."
          trufflehog filesystem \
            --fail \
            --fail-on-scan-errors \
            --results=verified,unknown \
            "''${scan_paths[@]}" || {
              trufflehog_status=$?
              if (( status == 0 )); then
                status=$trufflehog_status
              fi
            }

          exit "$status"
        '';
      };
    in
    {
      packages = forEachSupportedSystem ({ pkgs }: {
        scan-secrets = scanSecrets pkgs;
      });
      apps = forEachSupportedSystem ({ pkgs }:
        let
          scanner = scanSecrets pkgs;
        in
        {
          default = {
            type = "app";
            program = "${scanner}/bin/scan-secrets";
            meta.description = "Scan repository files for secrets";
          };
        });
      devShells = forEachSupportedSystem ({ pkgs }:
        let
          scanner = scanSecrets pkgs;
          preCommitHook = pkgs.writeShellScript "pre-commit-secrets" ''
            exec ${scanner}/bin/scan-secrets --staged
          '';
        in
        {
          default = pkgs.mkShell {
            venvDir = ".venv";
            packages = with pkgs; [ python312 just neovim nushell cookiecutter openapi-generator-cli git ripsecrets trufflehog scanner ] ++
              (with pkgs.python312Packages; [
                pip
                uv
                venvShellHook
              ]);
            shellHook = ''
              export PS1="[nix-shell] $PS1"
              if git rev-parse --show-toplevel >/dev/null 2>&1; then
                hook_path="$(git rev-parse --git-path hooks/pre-commit)"
                if [ -L "$hook_path" ] && [ "$(readlink "$hook_path")" = "${preCommitHook}" ]; then
                  :
                elif [ -L "$hook_path" ] && [[ "$(readlink "$hook_path")" == /nix/store/*-pre-commit-secrets ]]; then
                  ln -sfn "${preCommitHook}" "$hook_path"
                elif [ -e "$hook_path" ] || [ -L "$hook_path" ]; then
                  echo "Existing pre-commit hook found at $hook_path; leaving it unchanged." >&2
                  echo "Add 'scan-secrets --staged' to that hook to enable secret scanning." >&2
                else
                  mkdir -p "$(dirname "$hook_path")"
                  ln -s "${preCommitHook}" "$hook_path"
                fi
              fi
            '';
          };
        });
    };
}
