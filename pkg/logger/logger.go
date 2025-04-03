// This file is part of MinIO Console Server
// Copyright (c) 2022 MinIO, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

package logger

import (
	"context"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"go/build"
	"net/http"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/minio/pkg/v3/env"

	"github.com/minio/console/pkg"
	"github.com/minio/pkg/v3/certs"

	"github.com/minio/console/pkg/logger/config"
	"github.com/minio/console/pkg/logger/message/log"
	"github.com/minio/highwayhash"
	"github.com/minio/minio-go/v7/pkg/set"
)

// HighwayHash key for logging in anonymous mode
var magicHighwayHash256Key = []byte("\x4b\xe7\x34\xfa\x8e\x23\x8a\xcd\x26\x3e\x83\xe6\xbb\x96\x85\x52\x04\x0f\x93\x5d\xa3\x9f\x44\x14\x97\xe0\x9d\x13\x22\xde\x36\xa0")

// Disable disables all logging, false by default. (used for "go test")
var Disable = false

// Level type
type Level int8

// Enumerated level types
const (
	InformationLvl Level = iota + 1
	ErrorLvl
	FatalLvl
)

var trimStrings []string

var matchingFuncNames = [...]string{
	"http.HandlerFunc.ServeHTTP",
	"cmd.serverMain",
	"cmd.StartGateway",
	// add more here ..
}

func (level Level) String() string {
	var lvlStr string
	switch level {
	case InformationLvl:
		lvlStr = "INFO"
	case ErrorLvl:
		lvlStr = "ERROR"
	case FatalLvl:
		lvlStr = "FATAL"
	}
	return lvlStr
}

// quietFlag: Hide startup messages if enabled
// jsonFlag: Display in JSON format, if enabled
var (
	quietFlag, jsonFlag, anonFlag bool
	// Custom function to format errors
	errorFmtFunc func(string, error, bool) string
)

// EnableQuiet - turns quiet option on.
func EnableQuiet() {
	quietFlag = true
}

// EnableJSON - outputs logs in json format.
func EnableJSON() {
	jsonFlag = true
	quietFlag = true
}

// EnableAnonymous - turns anonymous flag
// to avoid printing sensitive information.
func EnableAnonymous() {
	anonFlag = true
}

// IsAnonymous - returns true if anonFlag is true
func IsAnonymous() bool {
	return anonFlag
}

// IsJSON - returns true if jsonFlag is true
func IsJSON() bool {
	return jsonFlag
}

// IsQuiet - returns true if quietFlag is true
func IsQuiet() bool {
	return quietFlag
}

// RegisterError registers the specified rendering function. This latter
// will be called for a pretty rendering of fatal errors.
func RegisterError(f func(string, error, bool) string) {
	errorFmtFunc = f
}

// Remove any duplicates and return unique entries.
func uniqueEntries(paths []string) []string {
	m := make(set.StringSet)
	for _, p := range paths {
		if !m.Contains(p) {
			m.Add(p)
		}
	}
	return m.ToSlice()
}

// Init sets the trimStrings to possible GOPATHs
// and GOROOT directories. Also append github.com/minio/minio
// This is done to clean up the filename, when stack trace is
// displayed when an errors happens.
func Init(goPath, goRoot string) {
	var goPathList []string
	var goRootList []string
	var defaultgoPathList []string
	var defaultgoRootList []string
	pathSeperator := ":"
	// Add all possible GOPATH paths into trimStrings
	// Split GOPATH depending on the OS type
	if runtime.GOOS == "windows" {
		pathSeperator = ";"
	}

	goPathList = strings.Split(goPath, pathSeperator)
	goRootList = strings.Split(goRoot, pathSeperator)
	defaultgoPathList = strings.Split(build.Default.GOPATH, pathSeperator)
	defaultgoRootList = strings.Split(build.Default.GOROOT, pathSeperator)

	// Add trim string "{GOROOT}/src/" into trimStrings
	trimStrings = []string{filepath.Join(runtime.GOROOT(), "src") + string(filepath.Separator)}

	// Add all possible path from GOPATH=path1:path2...:pathN
	// as "{path#}/src/" into trimStrings
	for _, goPathString := range goPathList {
		trimStrings = append(trimStrings, filepath.Join(goPathString, "src")+string(filepath.Separator))
	}

	for _, goRootString := range goRootList {
		trimStrings = append(trimStrings, filepath.Join(goRootString, "src")+string(filepath.Separator))
	}

	for _, defaultgoPathString := range defaultgoPathList {
		trimStrings = append(trimStrings, filepath.Join(defaultgoPathString, "src")+string(filepath.Separator))
	}

	for _, defaultgoRootString := range defaultgoRootList {
		trimStrings = append(trimStrings, filepath.Join(defaultgoRootString, "src")+string(filepath.Separator))
	}

	// Remove duplicate entries.
	trimStrings = uniqueEntries(trimStrings)

	// Add "github.com/minio/minio" as the last to cover
	// paths like "{GOROOT}/src/github.com/minio/minio"
	// and "{GOPATH}/src/github.com/minio/minio"
	trimStrings = append(trimStrings, filepath.Join("github.com", "minio", "minio")+string(filepath.Separator))
}

func trimTrace(f string) string {
	for _, trimString := range trimStrings {
		f = strings.TrimPrefix(filepath.ToSlash(f), filepath.ToSlash(trimString))
	}
	return filepath.FromSlash(f)
}

func getSource(level int) string {
	pc, file, lineNumber, ok := runtime.Caller(level)
	if ok {
		// Clean up the common prefixes
		file = trimTrace(file)
		_, funcName := filepath.Split(runtime.FuncForPC(pc).Name())
		return fmt.Sprintf("%v:%v:%v()", file, lineNumber, funcName)
	}
	return ""
}

// getTrace method - creates and returns stack trace
func getTrace(traceLevel int) []string {
	var trace []string
	pc, file, lineNumber, ok := runtime.Caller(traceLevel)

	for ok && file != "" {
		// Clean up the common prefixes
		file = trimTrace(file)
		// Get the function name
		_, funcName := filepath.Split(runtime.FuncForPC(pc).Name())
		// Skip duplicate traces that start with file name, "<autogenerated>"
		// and also skip traces with function name that starts with "runtime."
		if !strings.HasPrefix(file, "<autogenerated>") &&
			!strings.HasPrefix(funcName, "runtime.") {
			// Form and append a line of stack trace into a
			// collection, 'trace', to build full stack trace
			trace = append(trace, fmt.Sprintf("%v:%v:%v()", file, lineNumber, funcName))

			// Ignore trace logs beyond the following conditions
			for _, name := range matchingFuncNames {
				if funcName == name {
					return trace
				}
			}
		}
		traceLevel++
		// Read stack trace information from PC
		pc, file, lineNumber, ok = runtime.Caller(traceLevel)
	}
	return trace
}

// Return the highway hash of the passed string
func hashString(input string) string {
	hh, _ := highwayhash.New(magicHighwayHash256Key)
	hh.Write([]byte(input))
	return hex.EncodeToString(hh.Sum(nil))
}

// Kind specifies the kind of errors log
type Kind string

const (
	// Minio errors
	Minio Kind = "CONSOLE"
	// All errors
	All Kind = "ALL"
)

// LogAlwaysIf prints a detailed errors message during
// the execution of the server.
func LogAlwaysIf(ctx context.Context, err error, errKind ...interface{}) {
	if err == nil {
		return
	}

	logIf(ctx, err, errKind...)
}

// LogIf prints a detailed errors message during
// the execution of the server
func LogIf(ctx context.Context, err error, errKind ...interface{}) {
	if err == nil {
		return
	}

	if errors.Is(err, context.Canceled) {
		return
	}
	logIf(ctx, err, errKind...)
}

// logIf prints a detailed errors message during
// the execution of the server.
func logIf(ctx context.Context, err error, errKind ...interface{}) {
	if Disable {
		return
	}
	logKind := string(Minio)
	if len(errKind) > 0 {
		if ek, ok := errKind[0].(Kind); ok {
			logKind = string(ek)
		}
	}
	req := GetReqInfo(ctx)

	if req == nil {
		req = &ReqInfo{API: "SYSTEM"}
	}

	kv := req.GetTags()
	tags := make(map[string]interface{}, len(kv))
	for _, entry := range kv {
		tags[entry.Key] = entry.Val
	}

	// Get full stack trace
	trace := getTrace(3)

	// Get the cause for the Error
	message := fmt.Sprintf("%v (%T)", err, err)
	if req.DeploymentID == "" {
		req.DeploymentID = GetGlobalDeploymentID()
	}

	entry := log.Entry{
		DeploymentID: req.DeploymentID,
		Level:        ErrorLvl.String(),
		LogKind:      logKind,
		RemoteHost:   req.RemoteHost,
		Host:         req.Host,
		RequestID:    req.RequestID,
		SessionID:    req.SessionID,
		UserAgent:    req.UserAgent,
		Time:         time.Now().UTC(),
		Trace: &log.Trace{
			Message:   message,
			Source:    trace,
			Variables: tags,
		},
	}

	if anonFlag {
		entry.SessionID = hashString(entry.SessionID)
		entry.RemoteHost = hashString(entry.RemoteHost)
		entry.Trace.Message = reflect.TypeOf(err).String()
		entry.Trace.Variables = make(map[string]interface{})
	}

	// Iterate over all logger targets to send the log entry
	for _, t := range SystemTargets() {
		if err := t.Send(entry, entry.LogKind); err != nil {
			if consoleTgt != nil {
				entry.Trace.Message = fmt.Sprintf("event(%#v) was not sent to Logger target (%#v): %#v", entry, t, err)
				consoleTgt.Send(entry, entry.LogKind)
			}
		}
	}
}

// ErrCritical is the value panic'd whenever CriticalIf is called.
var ErrCritical struct{}

// CriticalIf logs the provided errors on the console. It fails the
// current go-routine by causing a `panic(ErrCritical)`.
func CriticalIf(ctx context.Context, err error, errKind ...interface{}) {
	if err != nil {
		LogIf(ctx, err, errKind...)
		panic(ErrCritical)
	}
}

// FatalIf is similar to Fatal() but it ignores passed nil errors
func FatalIf(err error, msg string, data ...interface{}) {
	if err == nil {
		return
	}
	fatal(err, msg, data...)
}

func applyDynamicConfigForSubSys(ctx context.Context, transport *http.Transport, subSys string) error {
	switch subSys {
	case config.LoggerWebhookSubSys:
		loggerCfg, err := LookupConfigForSubSys(config.LoggerWebhookSubSys)
		if err != nil {
			LogIf(ctx, fmt.Errorf("unable to load logger webhook config: %w", err))
			return err
		}
		userAgent := getUserAgent()
		for n, l := range loggerCfg.HTTP {
			if l.Enabled {
				l.LogOnce = LogOnceIf
				l.UserAgent = userAgent
				l.Transport = NewHTTPTransportWithClientCerts(transport, l.ClientCert, l.ClientKey)
				loggerCfg.HTTP[n] = l
			}
		}
		err = UpdateSystemTargets(loggerCfg)
		if err != nil {
			LogIf(ctx, fmt.Errorf("unable to update logger webhook config: %w", err))
			return err
		}
	case config.AuditWebhookSubSys:
		loggerCfg, err := LookupConfigForSubSys(config.AuditWebhookSubSys)
		if err != nil {
			LogIf(ctx, fmt.Errorf("unable to load audit webhook config: %w", err))
			return err
		}
		userAgent := getUserAgent()
		for n, l := range loggerCfg.AuditWebhook {
			if l.Enabled {
				l.LogOnce = LogOnceIf
				l.UserAgent = userAgent
				l.Transport = NewHTTPTransportWithClientCerts(transport, l.ClientCert, l.ClientKey)
				loggerCfg.AuditWebhook[n] = l
			}
		}

		err = UpdateAuditWebhookTargets(loggerCfg)
		if err != nil {
			LogIf(ctx, fmt.Errorf("unable to update audit webhook targets: %w", err))
			return err
		}
	}
	return nil
}

// InitializeLogger :
func InitializeLogger(ctx context.Context, transport *http.Transport) error {
	err := applyDynamicConfigForSubSys(ctx, transport, config.LoggerWebhookSubSys)
	if err != nil {
		return err
	}
	err = applyDynamicConfigForSubSys(ctx, transport, config.AuditWebhookSubSys)
	if err != nil {
		return err
	}

	if enable, _ := config.ParseBool(env.Get(EnvLoggerJSONEnable, "")); enable {
		EnableJSON()
	}
	if enable, _ := config.ParseBool(env.Get(EnvLoggerAnonymousEnable, "")); enable {
		EnableAnonymous()
	}
	if enable, _ := config.ParseBool(env.Get(EnvLoggerQuietEnable, "")); enable {
		EnableQuiet()
	}

	return nil
}

func getUserAgent() string {
	userAgentParts := []string{}
	// Helper function to concisely append a pair of strings to a
	// the user-agent slice.
	uaAppend := func(p, q string) {
		userAgentParts = append(userAgentParts, p, q)
	}
	uaAppend("Console (", runtime.GOOS)
	uaAppend("; ", runtime.GOARCH)
	uaAppend(") Console/", pkg.Version)
	uaAppend(" Console/", pkg.ReleaseTag)
	uaAppend(" Console/", pkg.CommitID)

	return strings.Join(userAgentParts, "")
}

// NewHTTPTransportWithClientCerts returns a new http configuration
// used while communicating with the cloud backends.
func NewHTTPTransportWithClientCerts(parentTransport *http.Transport, clientCert, clientKey string) *http.Transport {
	transport := parentTransport.Clone()
	if clientCert != "" && clientKey != "" {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		c, err := certs.NewManager(ctx, clientCert, clientKey, tls.LoadX509KeyPair)
		if err != nil {
			LogIf(ctx, fmt.Errorf("failed to load client key and cert, please check your endpoint configuration: %s",
				err.Error()))
		}
		if c != nil {
			c.UpdateReloadDuration(10 * time.Second)
			c.ReloadOnSignal(syscall.SIGHUP) // allow reloads upon SIGHUP
			transport.TLSClientConfig.GetClientCertificate = c.GetClientCertificate
		}
	}
	return transport
}
