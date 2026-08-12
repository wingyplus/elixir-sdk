package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/template"
	"unicode"
)

// render-template MODULE_NAME TEMPLATE_DIR OUT_DIR
//
// Walks TEMPLATE_DIR and writes the result to OUT_DIR. Files ending in ".tmpl"
// are rendered as Go text/templates and lose the suffix; everything else is
// copied verbatim. Path segments containing "{{" are rendered too, so a
// template can name a file after the module (e.g. lib/{{.ModulePackage}}.ex.tmpl).
//
// Available fields:
//
//	.ModuleName     the Dagger module name, verbatim  ("my-module")
//	.ModuleType     the Elixir module name            ("MyModule")
//	.ModulePackage  the Elixir application name       ("my_module")
//
// ModuleType and ModulePackage MUST stay byte-for-byte identical to
// toElixirModuleName/toElixirApplicationName in ../../runtime/main.dang: the
// runtime derives the entrypoint's module name from the Dagger module name at
// call time, while this helper derives the defmodule name at init time. If the
// two ever disagree, the generated module compiles but the runtime looks up a
// module that does not exist. That is why this does not use a general-purpose
// case library — see TestNameConversionsMatchDang.
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

var (
	reAcronymBoundary = regexp.MustCompile(`([A-Z]+)([A-Z][a-z])`)
	reCaseBoundary    = regexp.MustCompile(`([a-z0-9])([A-Z])`)
	reNonAlphanumeric = regexp.MustCompile(`[^A-Za-z0-9]+`)
)

// elixirAppName mirrors toElixirApplicationName in runtime/main.dang.
func elixirAppName(name string) string {
	s := reAcronymBoundary.ReplaceAllString(name, "${1}_${2}")
	s = reCaseBoundary.ReplaceAllString(s, "${1}_${2}")
	s = reNonAlphanumeric.ReplaceAllString(s, "_")
	s = strings.Trim(s, "_")
	return strings.ToLower(s)
}

// elixirModuleName mirrors toElixirModuleName in runtime/main.dang.
func elixirModuleName(name string) string {
	parts := strings.Split(elixirAppName(name), "_")
	for i, part := range parts {
		if part == "" {
			continue
		}
		runes := []rune(part)
		runes[0] = unicode.ToUpper(runes[0])
		parts[i] = string(runes)
	}
	return strings.Join(parts, "")
}

func run(args []string) error {
	if len(args) != 3 {
		return fmt.Errorf("usage: render-template MODULE_NAME TEMPLATE_DIR OUT_DIR")
	}

	moduleName := args[0]
	templateDir := args[1]
	outDir := args[2]

	appName := elixirAppName(moduleName)
	if appName == "" {
		return fmt.Errorf("module name %q has no alphanumeric characters", moduleName)
	}

	data := map[string]string{
		"ModuleName":    moduleName,
		"ModuleType":    elixirModuleName(moduleName),
		"ModulePackage": appName,
	}

	return filepath.WalkDir(templateDir, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(templateDir, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}

		dstRel := strings.TrimSuffix(rel, ".tmpl")
		if strings.Contains(dstRel, "{{") {
			pathTmpl, err := template.New("path-" + rel).Parse(dstRel)
			if err != nil {
				return err
			}
			var pathBuf bytes.Buffer
			if err := pathTmpl.Execute(&pathBuf, data); err != nil {
				return err
			}
			dstRel = pathBuf.String()
		}
		dst := filepath.Join(outDir, dstRel)
		if entry.IsDir() {
			return os.MkdirAll(dst, 0o755)
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("template symlinks are not supported: %s", rel)
		}
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}

		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if !strings.HasSuffix(rel, ".tmpl") {
			return os.WriteFile(dst, contents, 0o644)
		}

		var buf bytes.Buffer
		tmpl, err := template.New(rel).Parse(string(contents))
		if err != nil {
			return err
		}
		if err := tmpl.Execute(&buf, data); err != nil {
			return err
		}
		return os.WriteFile(dst, buf.Bytes(), 0o644)
	})
}
