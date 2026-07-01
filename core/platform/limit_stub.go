//go:build cgo && !android && !ohos

package platform

func ShouldBlockConnection() bool {
	return false
}
