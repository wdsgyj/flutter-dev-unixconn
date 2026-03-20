package proxy

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/wdsgyj/unixproxy-go"
)

type Options struct {
	ClientTimeout   time.Duration
	ClientFactory   unixproxy.ClientFactory
	TransportConfig unixproxy.TransportConfigurer
	ClientConfig    unixproxy.HTTPClientConfigurer
	OnTrace         func(unixproxy.TraceEvent)
}

type Manager struct {
	mu      sync.Mutex
	nextID  int64
	byID    map[int64]*instance
	byPath  map[string]*instance
	started bool
}

type instance struct {
	id         int64
	socketPath string
	server     *unixproxy.Server
	listener   net.Listener

	done chan error
	once sync.Once

	unregisterTrace func()
}

func NewManager() *Manager {
	return &Manager{
		byID:   make(map[int64]*instance),
		byPath: make(map[string]*instance),
	}
}

func (m *Manager) Start(socketPath string, options Options) (int64, error) {
	if socketPath == "" {
		return 0, fmt.Errorf("socket path is required")
	}

	m.mu.Lock()
	if running := m.byPath[socketPath]; running != nil {
		id := running.id
		m.mu.Unlock()
		return id, nil
	}
	m.nextID++
	id := m.nextID
	m.mu.Unlock()

	listener, err := prepareListener(socketPath)
	if err != nil {
		return 0, err
	}

	serverOptions := make([]unixproxy.Option, 0, 1)
	if options.ClientTimeout > 0 {
		serverOptions = append(
			serverOptions,
			unixproxy.WithClientTimeout(options.ClientTimeout),
		)
	}
	if options.ClientFactory != nil {
		serverOptions = append(
			serverOptions,
			unixproxy.WithClientFactory(options.ClientFactory),
		)
	}
	if options.TransportConfig != nil {
		serverOptions = append(
			serverOptions,
			unixproxy.WithTransportConfig(options.TransportConfig),
		)
	}
	if options.ClientConfig != nil {
		serverOptions = append(
			serverOptions,
			unixproxy.WithClientConfig(options.ClientConfig),
		)
	}

	server := unixproxy.NewServer(socketPath, serverOptions...)
	inst := &instance{
		id:         id,
		socketPath: socketPath,
		server:     server,
		listener:   listener,
		done:       make(chan error, 1),
	}
	if options.OnTrace != nil {
		inst.unregisterTrace = server.RegisterTraceListener(
			unixproxy.TraceListenerFunc(options.OnTrace),
		)
	}

	m.mu.Lock()
	if running := m.byPath[socketPath]; running != nil {
		m.mu.Unlock()
		_ = listener.Close()
		return running.id, nil
	}
	m.byID[id] = inst
	m.byPath[socketPath] = inst
	m.mu.Unlock()

	go func() {
		err := server.Serve(listener)
		inst.done <- err
		close(inst.done)
		m.remove(inst)
	}()

	return id, nil
}

func (m *Manager) Stop(id int64) error {
	m.mu.Lock()
	inst := m.byID[id]
	m.mu.Unlock()

	if inst == nil {
		return fmt.Errorf("proxy handle %d does not exist", id)
	}

	var stopErr error
	inst.once.Do(func() {
		if inst.unregisterTrace != nil {
			inst.unregisterTrace()
			inst.unregisterTrace = nil
		}
		stopErr = inst.server.Close()
	})
	if stopErr != nil {
		return stopErr
	}

	for err := range inst.done {
		if err != nil {
			return err
		}
	}
	return nil
}

func (m *Manager) remove(inst *instance) {
	m.mu.Lock()
	defer m.mu.Unlock()

	current := m.byID[inst.id]
	if current == inst {
		delete(m.byID, inst.id)
	}
	if currentByPath := m.byPath[inst.socketPath]; currentByPath == inst {
		delete(m.byPath, inst.socketPath)
	}
}

func prepareListener(socketPath string) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(socketPath), 0o755); err != nil {
		return nil, fmt.Errorf("create socket dir: %w", err)
	}
	if err := os.Remove(socketPath); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("remove stale socket: %w", err)
	}
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("listen on unix socket: %w", err)
	}
	return listener, nil
}
