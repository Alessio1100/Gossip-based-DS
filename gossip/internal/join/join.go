package join

import (
	"encoding/json"
	"fmt"
	"log"
	"net"

	"Gossip/internal/membership"
	"Gossip/internal/util"
)

// Funzione per inviare una richiesta di JOIN al nodo bootstrap
func SendJoinRequest(bootstrapIP, bootstrapPort string, self util.NodeStatus, localMembership *membership.MembershipList) error {
	addr := fmt.Sprintf("%s:%s", bootstrapIP, bootstrapPort)

	// Costruisci il messaggio di JOIN
	joinMessage := util.JoinMessage{
		Type:   "join",
		Sender: self,
	}

	// Serializza il messaggio
	data, err := json.Marshal(joinMessage)
	if err != nil {
		return fmt.Errorf("errore serializzazione messaggio JOIN: %v", err)
	}

	// Invia il messaggio UDP al nodo bootstrap
	conn, err := net.Dial("udp", addr)
	if err != nil {
		return fmt.Errorf("errore connessione UDP al nodo bootstrap: %v", err)
	}
	defer conn.Close()

	_, err = conn.Write(data)
	if err != nil {
		return fmt.Errorf("errore invio messaggio JOIN: %v", err)
	}

	log.Printf("[JOIN] Richiesta JOIN inviata a %s\n", addr)

	// Attesa della JOIN_ACK
	buffer := make([]byte, 4096)
	n, err := conn.Read(buffer)
	if err != nil {
		return fmt.Errorf("errore ricezione JOIN_ACK: %v", err)
	}

	// Deserializza la risposta
	var ack util.GossipMessage
	err = json.Unmarshal(buffer[:n], &ack)
	if err != nil {
		return fmt.Errorf("errore parsing JOIN_ACK: %v", err)
	}

	// Aggiorna la Membership List locale con i dati ricevuti
	for _, node := range ack.Membership {
		localMembership.AddOrUpdateNode(node)
	}
	log.Printf("[JOIN] Ricevuta Membership List da %s con %d nodi\n", addr, len(ack.Membership))

	return nil
}

// Funzione per gestire la ricezione di una richiesta JOIN da un nuovo nodo
func HandleJoinRequest(data []byte, addr net.Addr, localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	// Parsing del messaggio ricevuto
	var joinMsg util.JoinMessage
	err := json.Unmarshal(data, &joinMsg)
	if err != nil {
		log.Printf("[JOIN] Errore parsing JOIN ricevuto: %v", err)
		return
	}

	newNode := joinMsg.Sender
	log.Printf("[JOIN] Ricevuta richiesta JOIN da %s (%s:%s)\n", newNode.ID, newNode.IP, newNode.Port)

	// Aggiungi il nuovo nodo alla Membership List locale
	localMembership.AddOrUpdateNode(newNode)

	// Prepara JOIN_ACK con Membership List attuale
	membershipList := localMembership.GetCopy()

	joinAck := util.GossipMessage{
		Type:       "join_ack",
		Sender:     selfNode,
		Membership: membershipList,
	}

	// Serializza JOIN_ACK
	ackData, err := json.Marshal(joinAck)
	if err != nil {
		log.Printf("[JOIN] Errore serializzazione JOIN_ACK: %v", err)
		return
	}

	// Rispondi al nodo richiedente
	conn, err := net.Dial("udp", addr.String())
	if err != nil {
		log.Printf("[JOIN] Errore connessione per JOIN_ACK: %v", err)
		return
	}
	defer conn.Close()

	_, err = conn.Write(ackData)
	if err != nil {
		log.Printf("[JOIN] Errore invio JOIN_ACK: %v", err)
		return
	}

	log.Printf("[JOIN] JOIN_ACK inviato a %s\n", addr.String())
}
