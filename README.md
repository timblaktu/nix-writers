# nix-writers

Enhanced nix-writers framework with comprehensive bash script validation and multi-language support.

## Features

This implementation provides four key bash script validation capabilities:

1. **ShellCheck Integration** - Static analysis with comprehensive error/warning detection
2. **Strict Mode Testing** - Validates `set -euo pipefail` compatibility  
3. **Function Dependency Analysis** - Extracts and analyzes function definitions and external command usage
4. **Variable Usage Analysis** - Detects unbound variable risks and provides recommendations

## Quick Start

```nix
# Create a validated bash script
mkBashScript {
  name = "my-script";
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Hello, validated world!"
  '';
}
```

## Validation System

The enhanced validation system includes:

- **mkValidatedScript** with validation options (enableShellCheck, enableStrictModeTest, etc.)
- **mkBashScript** with all validations enabled by default
- **Build-time validation helpers** that create analysis reports
- **Runtime tests** that validate script quality during `nix flake check`
- **Comprehensive error reporting** with severity levels

## Architecture

### Core Writers

| Language | Function | Validation |
|----------|----------|------------|
| Bash | `mkBashScript` | ShellCheck + strict mode + dependency analysis |
| Python | `mkPythonScript` | Syntax + PEP8 with flake8 |
| PowerShell | `mkPowerShellScript` | AST validation |

### Script Examples

**Simple Bash Script:**
```nix
hello-script = mkBashScript {
  name = "hello";
  text = /* bash */ ''
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Hello from validated script!"
  '';
};
```

**Python with Dependencies:**
```nix
system-info = mkPythonScript {
  name = "system-info";
  deps = with pkgs.python3Packages; [ psutil ];
  text = /* python */ ''
    import psutil
    print(f"CPU cores: {psutil.cpu_count()}")
    print(f"Memory: {psutil.virtual_memory().total // (1024**3)} GB")
  '';
};
```

**Script with Tests:**
```nix
my-tool = mkBashScript {
  name = "my-tool";
  text = /* bash */ ''
    echo "Working correctly"
  '';
  tests = {
    basic = writers.testBash "test-my-tool" ''
      ${my-tool}/bin/my-tool | grep -q "Working correctly"
    '';
  };
};
```

## Available Writers

### Script Writers (with automatic syntax checking)
- `mkBashScript` / `writeBash` - Bash with comprehensive validation
- `mkPythonScript` / `writePython3` - Python with syntax checking
- `writeFishBin` / `writeFish` - Fish shell
- `writeJSBin` / `writeJS` - Node.js
- `writeRubyBin` / `writeRuby` - Ruby

### Compiled Language Writers
- `writeC` / `writeCBin` - C with gcc
- `writeRustBin` - Rust with rustc
- `writeGo` - Go programs
- `writeHaskellBin` - Haskell

### Configuration Writers
- `writeJSON`, `writeYAML`, `writeTOML` - With validation

## Key Benefits

**Traditional approach:**
- Runtime errors 💥
- Missing dependencies 📦❌  
- No validation ⚠️
- Hard to test 🧪❌

**nix-writers approach:**
- Build-time validation ✅
- Automatic dependencies 📦✅
- Comprehensive analysis ✅
- Built-in testing 🧪✅

## Testing

All scripts are automatically validated during build time. Run comprehensive checks:

```bash
nix flake check
```

This validates:
- Syntax correctness
- ShellCheck compliance
- Strict mode compatibility
- Function dependency resolution
- Variable usage safety

## File Structure

```
nix-writers/
├── README.md          # This file
├── flake.nix          # Flake configuration
├── default.nix       # Main module
├── bash.nix          # Bash script writers
├── python.nix        # Python script writers
├── powershell.nix    # PowerShell script writers
└── tests.nix         # Test framework
```

## How It Works

1. **Define scripts** using language-specific writers
2. **Build-time validation** catches syntax errors, analyzes dependencies
3. **Dependency injection** ensures libraries are available
4. **Testing integration** with `nix flake check`
5. **Quality assurance** through comprehensive static analysis

The validation happens automatically during script builds, providing ShellCheck analysis, strict mode testing, function dependency analysis, and variable usage analysis for all bash scripts created with mkBashScript.