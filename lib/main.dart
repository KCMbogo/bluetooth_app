// ignore_for_file: library_private_types_in_public_api, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart'; // Add for better permission handling

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

class _BluetoothAppState extends State<BluetoothApp>
    with WidgetsBindingObserver {
  // Bluetooth state
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  // List of available and paired devices
  final List<BluetoothDevice> _devicesList = [];
  final List<BluetoothDevice> _pairedDevicesList = [];

  // Subscription to bluetooth state changes
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  StreamSubscription<BluetoothState>? _stateStreamSubscription;
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

  // Timer for discovery timeout
  Timer? _discoveryTimer;

  // Flag to track if discovery was manually stopped
  bool _discoveryStopped = false;

  // Timer for checking connection state
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();

    // Register observer for lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Request necessary permissions
    _requestPermissions();

    // Get current Bluetooth state
    FlutterBluetoothSerial.instance.state.then((state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
        });
      }
    });

    // Listen for Bluetooth state changes
    _stateStreamSubscription = FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
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
                // Start connection check timer
                _startConnectionCheck();
              }
            });
          }
        });

    // Get paired devices if Bluetooth is already on
    if (_bluetoothState == BluetoothState.STATE_ON) {
      _getPairedDevices();
      _startConnectionCheck();
    }
  }

  // Request necessary permissions for Bluetooth scanning
  Future<void> _requestPermissions() async {
    // For Android 12+ we need more permissions
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
    await Permission.bluetoothAdvertise.request();

    // Check if permissions are granted
    bool hasPermissions =
        await Permission.bluetooth.isGranted &&
        await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted &&
        await Permission.location.isGranted;

    if (!hasPermissions) {
      throw 'Required Bluetooth permissions not granted';
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
      // Stop discovery if running
      if (_isDiscovering) {
        _stopDiscovery();
      }
    }
  }

  @override
  void dispose() {
    // Remove observer for lifecycle events
    WidgetsBinding.instance.removeObserver(this);

    // Cancel discovery subscription
    _streamSubscription?.cancel();
    _stateStreamSubscription?.cancel();

    // Cancel discovery timer
    _discoveryTimer?.cancel();

    // Cancel connection check timer
    _connectionCheckTimer?.cancel();

    // Close connection
    _disconnectFromDevice();

    // Dispose text controller
    _messageController.dispose();

    super.dispose();
  }

  // Toggle Bluetooth function
  Future<void> _toggleBluetooth() async {
    try {
      if (_bluetoothState == BluetoothState.STATE_OFF) {
        await FlutterBluetoothSerial.instance.requestEnable();
      } else if (_bluetoothState == BluetoothState.STATE_ON) {
        // First try to close any active connections
        _disconnectFromDevice();

        // Then wait a moment before disabling
        await Future.delayed(const Duration(milliseconds: 500));

        // Try to disable Bluetooth
        bool? disableResult =
            await FlutterBluetoothSerial.instance.requestDisable();

        if (!disableResult! && mounted) {
          // If automatic disable fails, show settings option
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please disable Bluetooth manually from system settings',
              ),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'SETTINGS',
                onPressed: _openBluetoothSettings,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error toggling Bluetooth: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Method to open system Bluetooth settings
  void _openBluetoothSettings() async {
    try {
      await FlutterBluetoothSerial.instance.openSettings();
    } catch (e) {
      print("Error opening Bluetooth settings: $e");
    }
  }

  // Get paired devices
  Future<void> _getPairedDevices() async {
    List<BluetoothDevice> devices = [];

    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      print("Error getting paired devices: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting paired devices: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _pairedDevicesList.clear();
        _pairedDevicesList.addAll(devices);
      });
    }
  }

  // Start device discovery with better filtering
  void _startDiscovery() async {
    // Request permissions first
    await _requestPermissions();

    // Cancel any existing discovery
    _stopDiscovery();

    setState(() {
      _devicesList.clear();
      _isDiscovering = true;
      _discoveryStopped = false;
    });

    try {
      _streamSubscription = FlutterBluetoothSerial.instance
          .startDiscovery()
          .listen((r) {
            // Only process if we haven't manually stopped
            if (mounted && !_discoveryStopped) {
              setState(() {
                // Check if device already exists in the list
                final existingIndex = _devicesList.indexWhere(
                  (device) => device.address == r.device.address,
                );

                // Only add/update if the device has a name (filters most unknown devices)
                if (r.device.name != null && r.device.name!.isNotEmpty) {
                  if (existingIndex >= 0) {
                    _devicesList[existingIndex] = r.device;
                  } else {
                    _devicesList.add(r.device);
                  }
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

      // Set a timeout for discovery
      _discoveryTimer = Timer(const Duration(seconds: 12), () {
        _stopDiscovery();
      });
    } catch (e) {
      _isDiscovering = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting discovery: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Stop discovery
  void _stopDiscovery() {
    _discoveryTimer?.cancel();
    if (_streamSubscription != null) {
      _discoveryStopped = true;
      _streamSubscription!.cancel();
      _streamSubscription = null;
    }

    if (mounted) {
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  void _startConnectionCheck() {
    // Cancel existing timer if any
    _connectionCheckTimer?.cancel();

    // Start periodic connection check
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted || _bluetoothState != BluetoothState.STATE_ON) {
        timer.cancel();
        return;
      }

      try {
        // Get current paired devices
        List<BluetoothDevice> devices =
            await FlutterBluetoothSerial.instance.getBondedDevices();

        // Check if any of our paired devices are connected
        for (var device in devices) {
          try {
            // Check if device is connected by attempting to get its connection state
            bool isDeviceConnected = false;
            try {
              // Try to get a connection to check if device is connected
              BluetoothConnection? testConnection =
                  await BluetoothConnection.toAddress(
                    device.address,
                  ).timeout(const Duration(milliseconds: 500));
              if (testConnection != null) {
                isDeviceConnected = true;
                await testConnection.close();
              }
            } catch (e) {
              // If we get a specific error, the device might be connected
              if (e.toString().contains('already connected') ||
                  e.toString().contains('already exists')) {
                isDeviceConnected = true;
              }
            }

            if (isDeviceConnected && !_isConnected) {
              // Device is connected but our app doesn't know about it
              if (mounted) {
                setState(() {
                  _isConnected = true;
                  _connectedDevice = device;
                });

                // Try to establish our own connection
                await _connectToDevice(device);
                break;
              }
            }
          } catch (e) {
            print('Error checking connection state: $e');
          }
        }
      } catch (e) {
        print('Error in connection check: $e');
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (!mounted) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      // First check if Bluetooth is enabled
      if (_bluetoothState != BluetoothState.STATE_ON) {
        throw 'Bluetooth is not enabled';
      }

      // Request permissions again before connecting
      await _requestPermissions();

      // Try to close any existing connection first
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
      }

      // Add a short delay before connection attempt
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if device is already connected in system
      bool isSystemConnected = false;
      try {
        // Try to get a connection to check if device is connected
        BluetoothConnection? testConnection =
            await BluetoothConnection.toAddress(
              device.address,
            ).timeout(const Duration(milliseconds: 500));
        if (testConnection != null) {
          isSystemConnected = true;
          await testConnection.close();
        }
      } catch (e) {
        // If we get a specific error, the device might be connected
        if (e.toString().contains('already connected') ||
            e.toString().contains('already exists')) {
          isSystemConnected = true;
        }
      }

      if (!isSystemConnected) {
        // Attempt to bond with the device first
        try {
          // First try to remove any existing bond
          await FlutterBluetoothSerial.instance.removeDeviceBondWithAddress(
            device.address,
          );
          await Future.delayed(const Duration(seconds: 1));

          // Now attempt to create a new bond
          bool? bonded = await FlutterBluetoothSerial.instance
              .bondDeviceAtAddress(device.address);
          if (bonded == true) {
            // Wait a moment for bonding to complete
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          print('Bonding error (may be already bonded): $e');
        }
      }

      // Implement connection retry logic
      int retryCount = 0;
      const maxRetries = 3;
      BluetoothConnection? tempConnection;

      while (retryCount <= maxRetries) {
        try {
          // Set a connection timeout
          tempConnection = await BluetoothConnection.toAddress(
            device.address,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw 'Connection timeout occurred',
          );

          // If we reach here, connection was successful
          break;
        } catch (e) {
          retryCount++;
          if (retryCount > maxRetries) {
            // Re-throw if we've exhausted retries
            rethrow;
          }

          // Log retry attempt
          print('Connection attempt $retryCount failed, retrying...');

          // Wait before retry with increasing delay
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }

      // Ensure we have a connection
      if (tempConnection == null) {
        throw 'Failed to establish connection after multiple attempts';
      }

      _connection = tempConnection;

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

      // Set up data listening with better error handling
      _connection!.input!.listen(
        (Uint8List data) {
          if (!mounted) return;

          try {
            // Convert the data to a string with error handling
            String dataString = utf8.decode(data, allowMalformed: true);

            setState(() {
              _messages.add("Received: $dataString");
            });
          } catch (e) {
            print("Error processing received data: $e");
            // Handle binary data that can't be decoded as UTF-8
            setState(() {
              _messages.add("Received: [Binary data]");
            });
          }
        },
        onError: (error) {
          print("Input stream error: $error");
          if (mounted) {
            _disconnectFromDevice();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connection error: $error'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
        onDone: () {
          print("Input stream closed");
          if (mounted) {
            _disconnectFromDevice();
          }
        },
        cancelOnError: false,
      );

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

      // Provide more specific error messages
      String errorMessage = 'Failed to connect';

      if (e.toString().contains('socket might closed')) {
        errorMessage =
            'Connection lost. Device may be out of range or turned off.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout. Device may not be responding.';
      } else if (e.toString().contains('bond')) {
        errorMessage = 'Failed to pair with device. Please try again.';
      } else if (e.toString().contains('permission')) {
        errorMessage =
            'Bluetooth permission denied. Please check app permissions.';
      } else if (e.toString().contains('security')) {
        errorMessage =
            'Security error. Please try pairing the device in system settings first.';
      } else {
        errorMessage = 'Connection error: ${e.toString()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'SETTINGS',
            onPressed: _openBluetoothSettings,
          ),
        ),
      );
    }
  }

  void _disconnectFromDevice() {
    // Safely close connection
    if (_connection != null) {
      try {
        _connection!.dispose();
      } catch (e) {
        print("Error disposing connection: $e");
      }
      _connection = null;
    }

    if (mounted) {
      setState(() {
        _isConnected = false;
        _connectedDevice = null;
      });
    }
  }

  // Send message to connected device with better error handling
  void _sendMessage(String message) {
    if (message.isEmpty) return;

    if (_connection != null && _connection!.isConnected) {
      try {
        _connection!.output.add(utf8.encode("$message\r\n"));
        _connection!.output.allSent.then((_) {
          if (mounted) {
            setState(() {
              _messages.add("Sent: $message");
              _messageController.clear();
            });
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error sending message: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not connected to any device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Update the device list item builder to remove pairing button
  Widget _buildDeviceListItem(BluetoothDevice device, bool isPaired) {
    bool isThisDeviceConnected = _connectedDevice?.address == device.address;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      elevation: 2,
      child: ListTile(
        leading: Icon(isPaired ? Icons.bluetooth_connected : Icons.bluetooth),
        title: Text(device.name ?? "Unknown device"),
        subtitle: Text(device.address),
        trailing:
            isThisDeviceConnected
                ? ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _disconnectFromDevice,
                  child: const Text('DISCONNECT'),
                )
                : ElevatedButton(
                  onPressed:
                      _isConnecting ? null : () => _connectToDevice(device),
                  child:
                      _isConnecting
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('CONNECT'),
                ),
      ),
    );
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
            color:
                _bluetoothState.isEnabled
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bluetooth: ${_bluetoothState.isEnabled ? "ON" : "OFF"}',
                  style: TextStyle(
                    color:
                        _bluetoothState.isEnabled ? Colors.green : Colors.red,
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
                            color:
                                _selectedTabIndex == 0
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
                            color:
                                _selectedTabIndex == 1
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
            child:
                _selectedTabIndex == 0 ? _buildDevicesTab() : _buildChatTab(),
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
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _stopDiscovery,
                        child: const Text('STOP'),
                      ),
                    ],
                  )
                  : ElevatedButton.icon(
                    onPressed:
                        _bluetoothState.isEnabled ? _startDiscovery : null,
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Paired Devices',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _pairedDevicesList.length,
              itemBuilder: (context, index) {
                return _buildDeviceListItem(_pairedDevicesList[index], true);
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Discovered Devices',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child:
                _devicesList.isEmpty && !_isDiscovering
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'No devices found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed:
                                _bluetoothState.isEnabled
                                    ? _startDiscovery
                                    : null,
                            child: const Text('SCAN AGAIN'),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _devicesList.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = _devicesList[index];
                        bool isPaired = _pairedDevicesList.any(
                          (d) => d.address == device.address,
                        );

                        // Skip if already in paired devices list
                        if (isPaired) {
                          return const SizedBox.shrink();
                        }

                        return _buildDeviceListItem(device, false);
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
          child:
              _isConnected
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
          child:
              _messages.isEmpty
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
                    reverse: false, // Show latest at the bottom
                    itemBuilder: (context, index) {
                      String message = _messages[index];
                      bool isSent = message.startsWith('Sent: ');

                      return Align(
                        alignment:
                            isSent
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4.0,
                            horizontal: 8.0,
                          ),
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: isSent ? Colors.blue[100] : Colors.grey[300],
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
                    hintText:
                        _isConnected
                            ? 'Type a message...'
                            : 'Connect to a device first',
                    border: const OutlineInputBorder(),
                    enabled: _isConnected,
                  ),
                  onSubmitted: _isConnected ? _sendMessage : null,
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed:
                    _isConnected && _messageController.text.isNotEmpty
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
}
