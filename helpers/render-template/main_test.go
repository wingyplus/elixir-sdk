package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestNameConversionsMatchDang pins the expected output of the two name
// conversions against the behaviour of toElixirApplicationName /
// toElixirModuleName in runtime/main.dang. The runtime computes the entrypoint's
// module name from the Dagger module name at call time; this helper computes the
// defmodule name at init time. A divergence produces a module that compiles but
// whose entrypoint names a module that does not exist, so the acronym and digit
// cases below are the ones worth guarding — a general-purpose case library gets
// them wrong (strcase.ToCamel("HTTPServer") == "Httpserver").
func TestNameConversionsMatchDang(t *testing.T) {
	for _, tc := range []struct {
		name    string
		appName string
		modName string
	}{
		{"my-module", "my_module", "MyModule"},
		{"my_module", "my_module", "MyModule"},
		{"myModule", "my_module", "MyModule"},
		{"MyModule", "my_module", "MyModule"},
		{"mymodule", "mymodule", "Mymodule"},
		{"HTTPServer", "http_server", "HttpServer"},
		{"MyHTTPServer", "my_http_server", "MyHttpServer"},
		{"http-server", "http_server", "HttpServer"},
		{"foo2bar", "foo2bar", "Foo2bar"},
		{"Foo-Bar_baz", "foo_bar_baz", "FooBarBaz"},
		{"--leading-and-trailing--", "leading_and_trailing", "LeadingAndTrailing"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := elixirAppName(tc.name); got != tc.appName {
				t.Errorf("elixirAppName(%q) = %q, want %q", tc.name, got, tc.appName)
			}
			if got := elixirModuleName(tc.name); got != tc.modName {
				t.Errorf("elixirModuleName(%q) = %q, want %q", tc.name, got, tc.modName)
			}
		})
	}
}

func TestRunRendersTemplate(t *testing.T) {
	tmplDir := t.TempDir()
	outDir := filepath.Join(t.TempDir(), "out")

	write(t, filepath.Join(tmplDir, "mix.exs.tmpl"), "app: :{{ .ModulePackage }}, mod: {{ .ModuleType }}\n")
	write(t, filepath.Join(tmplDir, "lib", "{{.ModulePackage}}.ex.tmpl"), "defmodule {{ .ModuleType }} do\nend\n")
	write(t, filepath.Join(tmplDir, ".formatter.exs"), "[verbatim: true]\n")

	if err := run([]string{"my-module", tmplDir, outDir}); err != nil {
		t.Fatalf("run: %v", err)
	}

	// .tmpl suffix stripped and contents rendered
	assertFile(t, filepath.Join(outDir, "mix.exs"), "app: :my_module, mod: MyModule\n")
	// templated path segment resolved
	assertFile(t, filepath.Join(outDir, "lib", "my_module.ex"), "defmodule MyModule do\nend\n")
	// non-.tmpl copied verbatim, keeping its name
	assertFile(t, filepath.Join(outDir, ".formatter.exs"), "[verbatim: true]\n")
}

func TestRunRejectsNameWithoutAlphanumerics(t *testing.T) {
	if err := run([]string{"---", t.TempDir(), filepath.Join(t.TempDir(), "out")}); err == nil {
		t.Fatal("expected an error for a module name with no alphanumeric characters")
	}
}

func write(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertFile(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(got) != want {
		t.Errorf("%s = %q, want %q", path, got, want)
	}
}
