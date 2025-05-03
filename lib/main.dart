// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const BluetoothApp(),
    );
  }
}

class BluetoothApp extends StatefulWidget {
  const BluetoothApp({super.key});

  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> with WidgetsBindingObserver {
  // Bluetooth state
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  
  // List of available and paired devices
  final List<BluetoothDevice> _devicesList = [];
  final List<BluetoothDevice> _pairedDevicesList = [];
  
  // Subscription to bluetooth state changes
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  bool _isDiscovering = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  
  // Selected device & connection
  BluetoothDevice? _connectedDevice;
  BluetoothConnection? _connection;
  
  // For tab view
  int _selectedTabIndex = 0;
  
  final TextEditingController _messageController = TextEditingController();
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    
    // Register observer for lifecycle events
    WidgetsBinding.instance.addObserver(this);
    
    // Get current Bluetooth state
    FlutterBluetoothSerial.instance.state.then((state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
        });
      }
    });
    
    // Listen for Bluetooth state changes
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
          
          // Reset devices list if Bluetooth is turned off
          if (state == BluetoothState.STATE_OFF) {
            _devicesList.clear();
            _pairedDevicesList.clear();
            _disconnectFromDevice();
          } else if (state == BluetoothState.STATE_ON) {
            // Get paired devices
            _getPairedDevices();
          }
        });
      }
    });
    
    // Get paired devices if Bluetooth is already on
    if (_bluetoothState == BluetoothState.STATE_ON) {
      _getPairedDevices();
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The app is visible and responding to user input
      // Refresh Bluetooth state
      FlutterBluetoothSerial.instance.state.then((btState) {
        if (mounted) {
          setState(() {
            _bluetoothState = btState;
            if (btState == BluetoothState.STATE_ON) {
              _getPairedDevices();
            }
          });
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // App is not visible to the user
      // You can clean up resources here
    }
  }

  @override
  void dispose() {
    // Remove observer for lifecycle events
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel discovery subscription
    _streamSubscription?.cancel();
    
    // Close connection
    _disconnectFromDevice();
    
    // Dispose text controller
    _messageController.dispose();
    
    super.dispose();
  }

  // Toggle Bluetooth function
  Future<void> _toggleBluetooth() async {
    if (_bluetoothState == BluetoothState.STATE_OFF) {
      await FlutterBluetoothSerial.instance.requestEnable();
    } else if (_bluetoothState == BluetoothState.STATE_ON) {
      await FlutterBluetoothSerial.instance.requestDisable();
    }
  }

  // Get paired devices
  Future<void> _getPairedDevices() async {
    List<BluetoothDevice> devices = [];
    
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      print("Error getting paired devices: $e");
    }
    
    if (mounted) {
      setState(() {
        _pairedDevicesList.clear();
        _pairedDevicesList.addAll(devices);
      });
    }
  }

  // Start device discovery
  void _startDiscovery() {
    // Cancel any existing discovery
    if (_streamSubscription != null) {
      _streamSubscription!.cancel();
    }
    
    setState(() {
      _devicesList.clear();
      _isDiscovering = true;
    });

    _streamSubscription = FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      if (mounted) {
        setState(() {
          // Check if device already exists in the list
          final existingIndex = _devicesList.indexWhere(
              (device) => device.address == r.device.address);
              
          if (existingIndex >= 0) {
            _devicesList[existingIndex] = r.device;
          } else {
            _devicesList.add(r.device);
          }
        });
      }
    });

    _streamSubscription!.onDone(() {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    });
  }

  // Connect to a device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (!mounted) return;
    
    setState(() {
      _isConnecting = true;
    });
    
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      
      if (!mounted) {
        // If widget was unmounted during async call, clean up and return
        _connection?.close();
        return;
      }
      
      setState(() {
        _isConnecting = false;
        _isConnected = true;
        _connectedDevice = device;
      });
      
      _connection!.input!.listen((Uint8List data) {
        if (!mounted) return;
        
        // Convert the data to a string
        String dataString = utf8.decode(data);
        
        setState(() {
          _messages.add("Received: $dataString");
        });
      }).onDone(() {
        if (mounted) {
          _disconnectFromDevice();
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.name ?? "Unknown device"}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isConnecting = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Disconnect from device
  void _disconnectFromDevice() {
    if (_connection != null && _connection!.isConnected) {
      _connection!.dispose();
      _connection = null;
    }
    
    setState(() {
      _isConnected = false;
      _connectedDevice = null;
    });
  }

  // Send message to connected device
  void _sendMessage(String message) {
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(utf8.encode(message + "\r\n"));
      
      setState(() {
        _messages.add("Sent: $message");
        _messageController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Controller'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 2,
        actions: [
          Switch(
            value: _bluetoothState.isEnabled,
            onChanged: (bool value) {
              _toggleBluetooth();
            },
            activeColor: Colors.white,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Status bar
          Container(
            color: _bluetoothState.isEnabled 
                ? Colors.green.withOpacity(0.2) 
                : Colors.red.withOpacity(0.2),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bluetooth: ${_bluetoothState.isEnabled ? "ON" : "OFF"}',
                  style: TextStyle(
                    color: _bluetoothState.isEnabled ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isConnected)
                  Text(
                    'Connected to: ${_connectedDevice?.name ?? "Unknown"}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          
          // Tab bar for navigation
          Container(
            color: Theme.of(context).primaryColor,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 0;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedTabIndex == 0 
                                ? Colors.white 
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.devices, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Devices',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 1;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedTabIndex == 1 
                                ? Colors.white 
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.message, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Tab views
          Expanded(
            child: _selectedTabIndex == 0 
                ? _buildDevicesTab() 
                : _buildChatTab(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDevicesTab() {
    return Column(
      children: [
        // Scan button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Devices',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _isDiscovering
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: _bluetoothState.isEnabled
                          ? _startDiscovery
                          : null,
                      icon: const Icon(Icons.search),
                      label: const Text('SCAN'),
                    ),
            ],
          ),
        ),
        
        // Divider
        const Divider(),
        
        // Paired devices section
        if (_pairedDevicesList.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Paired Devices',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _pairedDevicesList.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = _pairedDevicesList[index];
                bool isThisDeviceConnected = _connectedDevice?.address == device.address;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  elevation: 2,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth_connected),
                    title: Text(device.name ?? "Unknown device"),
                    subtitle: Text(device.address),
                    trailing: isThisDeviceConnected
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('DISCONNECT'),
                          onPressed: _disconnectFromDevice,
                        )
                      : ElevatedButton(
                          child: const Text('CONNECT'),
                          onPressed: _isConnecting 
                              ? null 
                              : () => _connectToDevice(device),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
        
        // Divider if both lists are present
        if (_pairedDevicesList.isNotEmpty && _devicesList.isNotEmpty)
          const Divider(),
        
        // Discovered devices section
        if (_bluetoothState.isEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Discovered Devices',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _devicesList.isEmpty && !_isDiscovering
                ? Center(
                    child: Text(
                      'No devices found. Try scanning again.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _devicesList.length,
                    itemBuilder: (context, index) {
                      BluetoothDevice device = _devicesList[index];
                      bool isThisDeviceConnected = _connectedDevice?.address == device.address;
                      bool isPaired = _pairedDevicesList.any(
                        (d) => d.address == device.address
                      );
                      
                      // Skip if already in paired devices list
                      if (isPaired) {
                        return const SizedBox.shrink();
                      }
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(device.name ?? "Unknown device"),
                          subtitle: Text(device.address),
                          trailing: isThisDeviceConnected
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('DISCONNECT'),
                                onPressed: _disconnectFromDevice,
                              )
                            : ElevatedButton(
                                child: const Text('CONNECT'),
                                onPressed: _isConnecting 
                                    ? null 
                                    : () => _connectToDevice(device),
                              ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildChatTab() {
    return Column(
      children: [
        // Connection status
        Container(
          padding: const EdgeInsets.all(16.0),
          child: _isConnected
              ? Text(
                  'Connected to ${_connectedDevice?.name ?? "Unknown device"}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : const Text(
                  'Not connected to any device',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        
        // Chat messages
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    _isConnected 
                        ? 'No messages yet. Send a message to start chatting.'
                        : 'Connect to a device to start chatting.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    String message = _messages[index];
                    bool isSent = message.startsWith('Sent: ');
                    
                    return Align(
                      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: isSent 
                              ? Colors.blue[100] 
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Text(
                          message.substring(message.indexOf(': ') + 2),
                          style: const TextStyle(fontSize: 16.0),
                        ),
                      ),
                    );
                  },
                ),
        ),
        
        // Message input
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: _isConnected ? 'Type a message...' : 'Connect to a device first',
                    border: const OutlineInputBorder(),
                    enabled: _isConnected,
                  ),
                  onSubmitted: _isConnected ? _sendMessage : null,
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _isConnected && _messageController.text.isNotEmpty
                    ? () => _sendMessage(_messageController.text)
                    : null,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // ignore: unused_element
  void _showConnectingDialog(BluetoothDevice device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connect to Device'),
          content: Text('Would you like to connect to ${device.name ?? "Unknown device"}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('CANCEL'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('CONNECT'),
              onPressed: () {
                Navigator.of(context).pop();
                _connectToDevice(device);
              },
            ),
          ],
        );
      },
    );
  }
}