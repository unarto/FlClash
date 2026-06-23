package main

import (
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"os"

	"github.com/liyue201/goqr"
)

func handleDecodeQrImage(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	img, _, err := image.Decode(file)
	if err != nil {
		return "", err
	}

	symbols, err := goqr.Recognize(img)
	if err != nil {
		return "", err
	}
	if len(symbols) == 0 {
		return "", errors.New("no qr code recognized")
	}
	return string(symbols[0].Payload), nil
}
