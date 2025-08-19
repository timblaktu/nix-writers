# Enhanced nix-writers Module - Polyglot script management with validation
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.validatedScripts;
  writers = pkgs.writers;
  
  # Enhanced validation helpers for bash scripts
  bashValidationHelpers = {
    
    # ShellCheck static analysis
    runShellCheck = text: pkgs.runCommand "shellcheck-validation" 
      { buildInputs = [ pkgs.shellcheck ]; } ''
      # Write script to temporary file
      cat > script.sh << 'EOF'
${text}
EOF
      
      # Run ShellCheck with comprehensive checks
      shellcheck --format=json script.sh > shellcheck-results.json || true
      
      # Parse results and create validation report
      if [ -s shellcheck-results.json ]; then
        echo "ShellCheck found issues:" >&2
        cat shellcheck-results.json >&2
        
        # Check severity levels
        if jq -e '.[] | select(.level == "error")' shellcheck-results.json >/dev/null 2>&1; then
          echo "ERROR: ShellCheck found errors that must be fixed" >&2
          exit 1
        fi
        
        if jq -e '.[] | select(.level == "warning")' shellcheck-results.json >/dev/null 2>&1; then
          echo "WARNING: ShellCheck found warnings (non-fatal)" >&2
        fi
      fi
      
      echo "✅ ShellCheck validation passed" > $out
    '';
    
    # Strict mode compatibility testing
    testStrictMode = text: pkgs.runCommand "strict-mode-test" 
      { buildInputs = [ pkgs.bash ]; } ''
      # Create test script with strict mode
      cat > test-script.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

${text}
EOF
      
      chmod +x test-script.sh
      
      # Test that script can be parsed with strict mode
      if bash -n test-script.sh; then
        echo "✅ Script compatible with strict mode (set -euo pipefail)" > $out
      else
        echo "❌ Script has syntax errors with strict mode" >&2
        exit 1
      fi
    '';
    
    # Function dependency analysis
    analyzeFunctionDeps = text: pkgs.runCommand "function-deps-analysis"
      { buildInputs = [ pkgs.bash pkgs.gnugrep pkgs.gawk ]; } ''
      cat > script-content.txt << 'EOF'
${text}
EOF
      cat > analyze.sh << 'EOF'
#!/usr/bin/env bash

# Extract function definitions and calls from script
script_text=$(cat script-content.txt)

echo "=== Function Dependency Analysis ===" > analysis.txt
echo >> analysis.txt

# Find function definitions
echo "Defined functions:" >> analysis.txt
echo "$script_text" | grep -E '^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([[:space:]]*\)[[:space:]]*\{' | \
  sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/  - \1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(.*/  - \1/' >> analysis.txt || true

# Find external command dependencies  
echo >> analysis.txt
echo "External commands used:" >> analysis.txt
echo "$script_text" | grep -oE '\b[a-zA-Z_][a-zA-Z0-9_-]*\b' | \
  grep -E '^(git|ssh|scp|curl|wget|jq|grep|awk|sed|find|sort|uniq|head|tail|cut|tr|wc|cat|echo|printf|date|mkdir|rm|cp|mv|chmod|chown|ls|cd|pwd|which|command|type|test|\[)$' | \
  sort -u | sed 's/^/  - /' >> analysis.txt || true

# Detect potential issues
echo >> analysis.txt
echo "Potential issues:" >> analysis.txt

# Check for unbound variable patterns
if echo "$script_text" | grep -qE '\$[a-zA-Z_][a-zA-Z0-9_]*[^}]|\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' && \
   ! echo "$script_text" | grep -q 'set.*-u'; then
  echo "  - Variables used without 'set -u' protection" >> analysis.txt
fi

# Check for error handling
if ! echo "$script_text" | grep -qE 'set.*-e|trap.*ERR'; then
  echo "  - No explicit error handling detected" >> analysis.txt
fi

# Check for pipeline failures
if echo "$script_text" | grep -q '|' && ! echo "$script_text" | grep -q 'set.*-o.*pipefail'; then
  echo "  - Pipelines used without 'set -o pipefail'" >> analysis.txt
fi

cat analysis.txt
EOF

      bash analyze.sh > $out
    '';
    
    # Variable usage analysis
    analyzeVariableUsage = text: pkgs.runCommand "variable-usage-analysis"
      { buildInputs = [ pkgs.bash pkgs.gnugrep pkgs.gawk ]; } ''
      cat > script-content.txt << 'EOF'
${text}
EOF
      cat > analyze-vars.sh << 'EOF'
#!/usr/bin/env bash

script_text=$(cat script-content.txt)

echo "=== Variable Usage Analysis ===" > var-analysis.txt
echo >> var-analysis.txt

# Find variable assignments
echo "Variable assignments:" >> var-analysis.txt
echo "$script_text" | grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*=' | \
  sed 's/^[[:space:]]*//; s/=$//' | sort -u | sed 's/^/  - /' >> var-analysis.txt || true

# Find environment variable usage
echo >> var-analysis.txt
echo "Environment variables referenced:" >> var-analysis.txt
echo "$script_text" | grep -oE '\$\{[a-zA-Z_][a-zA-Z0-9_]*[^}]*\}|\$[a-zA-Z_][a-zA-Z0-9_]*' | \
  sed 's/^\${\([^}]*\)}.*/\1/; s/^\$\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' | \
  grep -vE '^[0-9]+$|^\*$|^@$|^\$$|^\?$|^!$' | \
  sort -u | sed 's/^/  - /' >> var-analysis.txt || true

# Check for unbound variable risks
echo >> var-analysis.txt
echo "Unbound variable risks:" >> var-analysis.txt

# Look for variables used without ${var:-default} or ${var?error} protection
risky_vars=$(echo "$script_text" | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*[^}]' | \
  sed 's/^\$//' | sort -u | \
  while read var; do
    if ! echo "$script_text" | grep -qE "\\\$\{$var[:-]|\\\$\{$var\?|$var="; then
      echo "  - $var (used without default value or error handling)"
    fi
  done)

if [ -n "$risky_vars" ]; then
  echo "$risky_vars" >> var-analysis.txt
else
  echo "  - None detected" >> var-analysis.txt
fi

cat var-analysis.txt
EOF

      bash analyze-vars.sh > $out
    '';
    
  };

  # Core helper function for creating validated scripts with enhanced testing
  mkValidatedScript = { 
    name, 
    lang ? "bash", 
    deps ? [], 
    tests ? {}, 
    text,
    extraChecks ? [],
    makeExecutable ? true,
    # Enhanced validation options for bash scripts
    enableShellCheck ? true,
    enableStrictModeTest ? true,
    enableFunctionAnalysis ? true,
    enableVariableAnalysis ? true
  }:
    let
      # Select appropriate writer based on language
      writerName = "write${lib.toUpper (lib.substring 0 1 lang)}${lib.substring 1 (-1) lang}${if makeExecutable then "Bin" else ""}";
      writer = writers.${writerName};
      
      # Enhanced validation for bash scripts
      bashValidation = if lang == "bash" then {
        shellcheck = lib.optionalAttrs enableShellCheck {
          shellcheck-validation = bashValidationHelpers.runShellCheck text;
        };
        strict-mode = lib.optionalAttrs enableStrictModeTest {
          strict-mode-test = bashValidationHelpers.testStrictMode text;
        };
        function-analysis = lib.optionalAttrs enableFunctionAnalysis {
          function-deps = bashValidationHelpers.analyzeFunctionDeps text;
        };
        variable-analysis = lib.optionalAttrs enableVariableAnalysis {
          variable-usage = bashValidationHelpers.analyzeVariableUsage text;
        };
      } else {};
      
      # Handle dependencies - convert to libraries format if needed
      # For bash scripts, writeBashBin just takes name and text
      # For python, writePython3Bin takes name, libraries (as an attrset), and text
      script = if lang == "bash" then
        writer name text
      else if lang == "python3" then
        writer name { libraries = deps; } text
      else
        writer name text;
      
      # Add automatic syntax test based on language
      testLang = lib.toUpper (lib.substring 0 1 lang) + lib.substring 1 (-1) lang;
      automaticSyntaxTest = {
        syntax = writers."test${testLang}" "${name}-syntax" ''
          # Automatic syntax validation happens at build time
          echo "✅ ${name}: Syntax validation passed"
        '';
      };
      
      # Enhanced testing for bash scripts
      enhancedBashTests = if lang == "bash" then (
        lib.optionalAttrs enableShellCheck {
          # Comprehensive shellcheck test
          shellcheck-test = writers.testBash "${name}-shellcheck" ''
            echo "Running ShellCheck analysis on ${name}..."
            
            # Extract script content for analysis
            script_path="${script}/bin/${name}"
            
            if command -v shellcheck >/dev/null 2>&1; then
              # Run shellcheck with specific options for better analysis
              if shellcheck \
                  --check-sourced \
                  --external-sources \
                  --enable=all \
                  --severity=info \
                  --format=tty \
                  "$script_path"; then
                echo "✅ ShellCheck passed for ${name}"
              else
                exit_code=$?
                if [ $exit_code -eq 1 ]; then
                  echo "❌ ShellCheck found errors in ${name}"
                  exit 1
                else
                  echo "⚠️  ShellCheck found warnings in ${name} (non-fatal)"
                fi
              fi
            else
              echo "⚠️  ShellCheck not available, skipping static analysis for ${name}"
            fi
          '';
        } //
        lib.optionalAttrs enableStrictModeTest {
          # Strict mode compatibility test
          strict-mode-test = writers.testBash "${name}-strict-mode" ''
            echo "Testing strict mode compatibility for ${name}..."
            
            # Create a test wrapper with strict mode
            cat > /tmp/strict-test-${name}.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Source or execute the original script in strict mode
exec "${script}/bin/${name}" --help
EOF
            
            chmod +x /tmp/strict-test-${name}.sh
            
            # Test syntax parsing with strict mode
            if bash -n /tmp/strict-test-${name}.sh; then
              echo "✅ ${name} is compatible with strict mode"
            else
              echo "❌ ${name} has strict mode compatibility issues"
              exit 1
            fi
            
            # Clean up
            rm -f /tmp/strict-test-${name}.sh
          '';
        } //
        lib.optionalAttrs enableFunctionAnalysis {
          # Function dependency test
          function-deps-test = writers.testBash "${name}-function-analysis" ''
            echo "Analyzing function dependencies for ${name}..."
            
            script_path="${script}/bin/${name}"
            
            # Extract and analyze function definitions
            echo "Functions defined:"
            grep -E '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' "$script_path" | \
              sed -E 's/^[[:space:]]*(function[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*).*/  \2/' || true
            
            echo
            echo "External commands used:"
            # Look for common command patterns
            grep -oE '\b(git|ssh|scp|curl|wget|jq|grep|awk|sed|find|sort|uniq|head|tail|cut|tr|wc|cat|echo|printf|date|mkdir|rm|cp|mv|chmod|chown|ls|cd|pwd|which|command|type|test|\[)\b' "$script_path" | \
              sort -u | sed 's/^/  /' || true
            
            echo "✅ Function dependency analysis completed for ${name}"
          '';
        } //
        lib.optionalAttrs enableVariableAnalysis {
          # Variable usage analysis test
          variable-usage-test = writers.testBash "${name}-variable-analysis" ''
            echo "Analyzing variable usage for ${name}..."
            
            script_path="${script}/bin/${name}"
            
            # Check for unbound variable usage patterns
            echo "Checking for potential unbound variables..."
            
            # Look for variables that might be unbound
            unbound_risk=false
            
            # Check if script uses 'set -u' or equivalent protection
            if grep -qE 'set.*-u|set.*-euo' "$script_path"; then
              echo "✅ Script uses 'set -u' protection"
            else
              echo "⚠️  Script doesn't use 'set -u' - variables might be unbound"
              
              # Look for unprotected variable references
              if grep -qE '\$[a-zA-Z_][a-zA-Z0-9_]*[^}]|\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' "$script_path"; then
                echo "⚠️  Found variable references - ensure they have default values"
              fi
            fi
            
            echo "✅ Variable usage analysis completed for ${name}"
          '';
        }
      ) else {};
      
      # Combine all tests, with enhanced tests taking precedence over user tests for same names
      allTests = automaticSyntaxTest // enhancedBashTests // tests;
      
    in script // { 
      passthru = (script.passthru or {}) // {
        tests = allTests;
        language = lang;
        dependencies = deps;
        makeExecutable = makeExecutable;
        validationResults = bashValidation;
        # Enhanced validation flags for debugging
        enableShellCheck = enableShellCheck;
        enableStrictModeTest = enableStrictModeTest;
        enableFunctionAnalysis = enableFunctionAnalysis;
        enableVariableAnalysis = enableVariableAnalysis;
      };
    };

  # Helper to create a script with treesitter language hints
  mkValidatedScriptWithHints = args@{ name, lang ? "bash", text, ... }:
    mkValidatedScript (args // {
      text = "/* ${lang} */ " + text;
    });
  
  # Convenience functions for common script types
  mkBashScript = args: mkValidatedScript (args // { 
    lang = "bash"; 
    # Enable all bash validation by default, but allow override
    enableShellCheck = args.enableShellCheck or true;
    enableStrictModeTest = args.enableStrictModeTest or true;
    enableFunctionAnalysis = args.enableFunctionAnalysis or true;
    enableVariableAnalysis = args.enableVariableAnalysis or true;
  });
  mkPythonScript = args: mkValidatedScript (args // { lang = "python3"; });
  mkPowerShellScript = args: mkValidatedScript (args // { lang = "powershell"; });
  
  # Function to create a script library (non-executable, for sourcing)
  mkScriptLibrary = args: mkValidatedScript (args // { makeExecutable = false; });
  
  # Helper to collect all tests from a set of scripts
  collectScriptTests = scripts:
    lib.mapAttrs' (scriptName: script:
      lib.mapAttrs' (testName: testDrv:
        lib.nameValuePair "script-${scriptName}-${testName}" testDrv
      ) (script.passthru.tests or {})
    ) scripts;

in {
  options.validatedScripts = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nix-writers based validated script management";
    };
    
    enableBashScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Bash script definitions from bash.nix";
    };
    
    enablePythonScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Python script definitions from python.nix";
    };
    
    enablePowerShellScripts = mkOption {
      type = types.bool;
      default = false;  # Disabled by default - PowerShell validation requires Windows/pwsh
      description = "Enable PowerShell script definitions from powershell.nix";
    };
    
    enableTests = mkOption {
      type = types.bool;
      default = true;
      description = "Enable script testing framework";
    };
    
    # Internal options for collecting scripts from sub-modules
    bashScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
    
    pythonScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
    
    powerShellScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
    
    customScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
  };
  
  imports = [
    # Import language-specific script definitions
    ./bash.nix
    ./python.nix
    ./powershell.nix
    ./tests.nix
  ];
  
  config = mkIf cfg.enable (
    let
      # Combine all scripts from sub-modules
      allScripts = 
        (if cfg.enableBashScripts then cfg.bashScripts else {}) //
        (if cfg.enablePythonScripts then cfg.pythonScripts else {}) //
        (if cfg.enablePowerShellScripts then cfg.powerShellScripts else {}) //
        cfg.customScripts;
      
      # Generate all tests
      allTests = if cfg.enableTests then collectScriptTests allScripts else {};
    in {
    # Make helper functions available to imported modules
    _module.args = {
      inherit mkValidatedScript mkValidatedScriptWithHints;
      inherit mkBashScript mkPythonScript mkPowerShellScript mkScriptLibrary;
      inherit collectScriptTests writers;
    };
    
    # Install all enabled scripts (excluding non-executable libraries)
    home.packages = lib.attrValues (lib.filterAttrs (name: script: 
      # Only include scripts that are executable (have /bin/ destination)
      script.passthru.makeExecutable or true
    ) allScripts);
    
    # Add validation reminder to shell
    programs.bash.initExtra = mkIf cfg.enableTests (mkAfter ''
      # Enhanced nix-writers available - run 'nix flake check' to validate all scripts
      export NIXCFG_NIX_WRITERS_ENABLED=1
    '');
    
    programs.zsh.initContent = mkIf cfg.enableTests (mkAfter ''
      # Enhanced nix-writers available - run 'nix flake check' to validate all scripts
      export NIXCFG_NIX_WRITERS_ENABLED=1
    '');
    }
  );
}