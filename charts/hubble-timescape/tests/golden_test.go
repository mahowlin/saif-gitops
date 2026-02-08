// Copyright (C) Isovalent, Inc. - All Rights Reserved.
//
// NOTICE: All information contained herein is, and remains the property of
// Isovalent Inc and its suppliers, if any. The intellectual and technical
// concepts contained herein are proprietary to Isovalent Inc and its suppliers
// and may be covered by U.S. and Foreign Patents, patents in process, and are
// protected by trade secret or copyright law.  Dissemination of this
// information or reproduction of this material is strictly forbidden unless
// prior written permission is obtained from Isovalent Inc.

//go:build helm

package tests

import (
	"errors"
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/isovalent/hubble-timescape/internal/difflib"
)

var updateGolden = flag.Bool("update-golden", false, "rewrite golden files")

func TestGolden(t *testing.T) {
	testValues, err := os.ReadDir("./values")
	require.NoError(t, err)

	for _, values := range testValues {
		t.Run(values.Name(), func(t *testing.T) {
			valuesFile := filepath.Clean(filepath.Join("./values", values.Name()))
			args := []string{"helm", "template", "..", "-f", valuesFile}
			t.Logf("running command: %q", strings.Join(args, " "))
			got, err := exec.Command(args[0], args[1:]...).Output() //nolint:gosec
			stdOut := ""
			if err != nil {
				exErr := &exec.ExitError{}
				if errors.As(err, &exErr) {
					stdOut = string(exErr.Stderr)
				}
			}
			require.NoError(t, err, stdOut)
			basepath := "./golden"
			golden := filepath.Clean(filepath.Join(basepath, values.Name()))
			if *updateGolden {
				err := os.WriteFile(golden, got, 0600)
				require.NoError(t, err)
				return
			}

			want, err := os.ReadFile(golden)
			if !os.IsNotExist(err) {
				require.NoError(t, err)
			}
			if os.IsNotExist(err) {
				require.Fail(t, "golden file does not exit")
			}

			diff, _ := difflib.GetUnifiedDiffString(difflib.UnifiedDiff{
				A:        difflib.SplitLines(string(want)),
				B:        difflib.SplitLines(string(got)),
				FromFile: "Expected",
				FromDate: "",
				ToFile:   "Actual",
				ToDate:   "",
				Context:  1,
			})
			if diff != "" {
				assert.Failf(t, "golden file missmatch. Run `make helm-gen-golden`", diff)
			}
		})
	}
}
