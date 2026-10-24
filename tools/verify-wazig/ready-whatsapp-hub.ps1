$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'adopted outbox acknowledged'
