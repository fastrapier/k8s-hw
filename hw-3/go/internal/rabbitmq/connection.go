package rabbitmq

import (
	"fmt"
	"log"

	amqp "github.com/rabbitmq/amqp091-go"
)

type Connection struct {
	Conn    *amqp.Connection
	Channel *amqp.Channel
}

// Dial connects to RabbitMQ at the given host using the provided credentials.
// host is the RabbitMQ address without scheme/port, e.g. "rabbitmq.local" or
// "rabbitmq.k8s-hw.svc.cluster.local".
func Dial(host, username, password string) (*Connection, error) {
	url := fmt.Sprintf("amqp://%s:%s@%s:5672/", username, password, host)
	conn, err := amqp.Dial(url)
	if err != nil {
		return nil, fmt.Errorf("amqp dial: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("open channel: %w", err)
	}

	return &Connection{Conn: conn, Channel: ch}, nil
}

func (c *Connection) DeclareExchange(name string) error {
	return c.Channel.ExchangeDeclare(
		name,
		"direct",
		true,  // durable
		false, // auto-deleted
		false, // internal
		false, // no-wait
		nil,
	)
}

func (c *Connection) DeclareAndBindQueue(queueName, exchangeName, routingKey string) (amqp.Queue, error) {
	q, err := c.Channel.QueueDeclare(
		queueName,
		true,  // durable
		false, // auto-delete
		false, // exclusive
		false, // no-wait
		nil,
	)
	if err != nil {
		return q, fmt.Errorf("queue declare: %w", err)
	}

	if err := c.Channel.QueueBind(queueName, routingKey, exchangeName, false, nil); err != nil {
		return q, fmt.Errorf("queue bind: %w", err)
	}

	return q, nil
}

func (c *Connection) Close() {
	if c.Channel != nil {
		if err := c.Channel.Close(); err != nil {
			log.Printf("close channel: %v", err)
		}
	}
	if c.Conn != nil {
		if err := c.Conn.Close(); err != nil {
			log.Printf("close connection: %v", err)
		}
	}
}
