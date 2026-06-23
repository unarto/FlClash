//go:build cgo && !android

package platform

func ShouldBlockConnection() bool {
	return false
}
