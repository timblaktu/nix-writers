{
  description = "Enhanced nix-writers utilities for validated polyglot script management";

  outputs = { self }: {
    # Export the home-manager module
    homeManagerModules = {
      default = import ./default.nix;
      nix-writers = import ./default.nix;
    };
    
    # Export helper functions for direct use (non-home-manager contexts)
    lib = {
      # Extract the core functions from the module
      mkValidatedScript = { lib, pkgs }: 
        let 
          writers = pkgs.writers;
          # Core helper function for creating validated scripts with tests
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
              
              # Handle dependencies - convert to libraries format if needed
              script = if lang == "bash" then
                writer name text
              else if lang == "python3" then
                writer name { libraries = deps; } text
              else
                writer name text;
              
              # Add automatic syntax test based on language  
              automaticSyntaxTest = if lang == "bash" then {
                syntax = pkgs.runCommand "${name}-syntax-test" {} ''
                  # Test bash syntax by parsing the script
                  ${pkgs.bash}/bin/bash -n ${script}/bin/${name}
                  echo "✅ ${name}: Bash syntax validation passed"
                  touch $out
                '';
              } else if lang == "python3" then {
                syntax = pkgs.runCommand "${name}-syntax-test" {} ''
                  # Test python syntax by compiling
                  ${pkgs.python3}/bin/python3 -m py_compile ${script}/bin/${name}
                  echo "✅ ${name}: Python syntax validation passed" 
                  touch $out
                '';
              } else {
                # No automatic syntax test for other languages
              };
              
              # Combine automatic and user-provided tests
              allTests = automaticSyntaxTest // tests;
              
            in script // { 
              passthru = (script.passthru or {}) // {
                tests = allTests;
                language = lang;
                dependencies = deps;
                makeExecutable = makeExecutable;
              };
            };
        in mkValidatedScript;
        
      # Convenience functions with enhanced validation
      mkBashScript = { lib, pkgs }: 
        let mkValidatedScript = self.lib.mkValidatedScript { inherit lib pkgs; };
        in args: mkValidatedScript (args // { 
          lang = "bash"; 
          # Enable all bash validation by default, but allow override
          enableShellCheck = args.enableShellCheck or true;
          enableStrictModeTest = args.enableStrictModeTest or true;
          enableFunctionAnalysis = args.enableFunctionAnalysis or true;
          enableVariableAnalysis = args.enableVariableAnalysis or true;
        });
        
      mkPythonScript = { lib, pkgs }: 
        let mkValidatedScript = self.lib.mkValidatedScript { inherit lib pkgs; };
        in args: mkValidatedScript (args // { lang = "python3"; });
        
      collectScriptTests = { lib, ... }: scripts:
        lib.foldl' (acc: scriptName: 
          let
            script = scripts.${scriptName};
            scriptTests = lib.mapAttrs' (testName: testDrv:
              lib.nameValuePair "script-${scriptName}-${testName}" testDrv
            ) (script.passthru.tests or {});
          in
          acc // scriptTests
        ) {} (lib.attrNames scripts);
    };
  };
}