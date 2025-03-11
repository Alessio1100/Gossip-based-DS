package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"Gossip/internal/gossip"
	//"Gossip/internal/leave"
	//"Gossip/internal/failure"
	"Gossip/internal/membership"
	"Gossip/internal/util"
)

func main() {
	// ✅ Inizializza il random per le selezioni casuali
	rand.Seed(time.Now().UnixNano())

	// ✅ Lettura variabili d'ambiente
	nodeID := os.Getenv("NODE_ID")
	nodeIP := os.Getenv("NODE_IP")
	nodePort := os.Getenv("NODE_PORT")
	seedNodes := os.Getenv("SEED_NODES") // Nodi iniziali da contattare per bootstrap (facoltativo)

	// ✅ Controllo parametri essenziali
	if nodeID == "" || nodeIP == "" || nodePort == "" {
		log.Fatal("NODE_ID, NODE_IP e NODE_PORT devono essere specificati come variabili d'ambiente.")
	}

	// ✅ Creazione Membership List vuota
	localMembership := membership.NewMembershipList()

	// ✅ Inserisce sé stesso nella Membership List
	selfNode := util.NodeStatus{
		ID:       fmt.Sprintf("%s:%s", nodeIP, nodePort), // Nodo unico sulla rete
		IP:       nodeIP,
		Port:     nodePort,
		Status:   "alive",
		LastSeen: time.Now().Format(time.RFC3339),
	}
	localMembership.AddOrUpdateNode(selfNode)
	log.Printf("[BOOTSTRAP] Nodo %s (%s:%s) inizializzato.\n", nodeID, nodeIP, nodePort)

	// ✅ Aggiunge SEED_NODES (se presenti)
	if seedNodes != "" {
		nodes := strings.Split(seedNodes, ",")
		for _, nodeStr := range nodes {
			parts := strings.Split(nodeStr, ":")
			if len(parts) == 2 {
				seedNode := util.NodeStatus{
					ID:       fmt.Sprintf("%s:%s", parts[0], parts[1]), // ID = "ip:port"
					IP:       parts[0],
					Port:     parts[1],
					Status:   "alive",
					LastSeen: time.Now().Format(time.RFC3339),
				}
				// Aggiunge solo se diverso da sé stesso
				if seedNode.ID != selfNode.ID {
					localMembership.AddOrUpdateNode(seedNode)
				}
			}
		}
		log.Printf("[BOOTSTRAP] Aggiunti %d SEED_NODES iniziali.\n", len(nodes))
	} else {
		log.Println("[BOOTSTRAP] Nessun SEED_NODES definito. Nodo isolato, in attesa di gossip.")
	}

	// ✅ Avvio server UDP per ricezione gossip
	go gossip.StartUDPServer(nodePort, localMembership, selfNode)

	// ✅ Avvio ciclo gossip periodico (push-pull + heartbeat)
	go gossip.StartGossipCycle(nodeID, nodeIP, nodePort, localMembership, selfNode)

	// ✅ Avvio failure detector
	//go failure.StartFailureDetector(localMembership)

	// ✅ Gestione LEAVE in chiusura
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	log.Println("[EXIT] Ricevuto segnale di interruzione. Comunicazione LEAVE alla rete.")
	//leave.SendLeaveMessage(localMembership, selfNode)
	log.Println("[EXIT] Nodo arrestato correttamente.")
}
