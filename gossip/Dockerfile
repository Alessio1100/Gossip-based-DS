# Usa l'immagine più recente di Go
FROM golang:1.24

# Imposta la directory di lavoro
WORKDIR /app

# Copia i file del modulo Go
COPY go.mod go.sum ./

# Scarica le dipendenze
RUN go mod tidy

# Copia il codice sorgente
COPY . .

# Compila il codice
RUN go build -o node ./cmd/node/main.go

# Comando di default per avviare il nodo
CMD [ "./node" ]
