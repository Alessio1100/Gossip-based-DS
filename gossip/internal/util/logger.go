package util

import (
	"log"
	"time"
)

// Funzione per loggare messaggi informativi
func Info(message string) {
	log.Printf("[INFO] [%s] %s", time.Now().Format(time.RFC3339), message)
}

// Funzione per loggare messaggi di avviso (warning)
func Warn(message string) {
	log.Printf("[WARN] [%s] %s", time.Now().Format(time.RFC3339), message)
}

// Funzione per loggare messaggi di errore
func Error(message string) {
	log.Printf("[ERROR] [%s] %s", time.Now().Format(time.RFC3339), message)
}

// Funzione per loggare messaggi di debug (opzionale, attivabile/disattivabile)
var DebugEnabled = true

func Debug(message string) {
	if DebugEnabled {
		log.Printf("[DEBUG] [%s] %s", time.Now().Format(time.RFC3339), message)
	}
}
