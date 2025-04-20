// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Bluetooth App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
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

class _BluetoothAppState extends State<BluetoothApp> {
  // Bluetooth state
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  
  // List of available devices
  final List<BluetoothDevice> _devicesList = [];
  
  // Subscription to bluetooth state changes
  late StreamSubscription<BluetoothDiscoveryResult> _streamSubscription;
  bool _isDiscovering = false;
  bool _discoveryInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Get current Bluetooth state
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });
    
    // Listen for Bluetooth state changes
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        
        // Reset devices list if Bluetooth is turned off
        if (state == BluetoothState.STATE_OFF) {
          _devicesList.clear();
        }
      });
    });
  }

  @override
  void dispose() {
    // Cancel discovery subscription if initialized
    if (_discoveryInitialized) {
      _streamSubscription.cancel();
    }
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

  // Start device discovery
  void _startDiscovery() {
    setState(() {
      _devicesList.clear();
      _isDiscovering = true;
    });

    _streamSubscription = FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      setState(() {
        _discoveryInitialized = true;
        // Check if device already exists in the list
        final existingIndex = _devicesList.indexWhere(
            (device) => device.address == r.device.address);
            
        if (existingIndex >= 0) {
          _devicesList[existingIndex] = r.device;
        } else {
          _devicesList.add(r.device);
        }
      });
    });

    _streamSubscription.onDone(() {
      setState(() {
        _isDiscovering = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Controller'),
      ),
      body: Column(
        children: <Widget>[
          SwitchListTile(
            title: const Text('Bluetooth'),
            value: _bluetoothState.isEnabled,
            onChanged: (bool value) {
              _toggleBluetooth();
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Available Devices'),
            trailing: _isDiscovering
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _bluetoothState.isEnabled
                        ? _startDiscovery
                        : null,
                    child: const Text('SCAN'),
                  ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = _devicesList[index];
                return ListTile(
                  title: Text(device.name ?? "Unknown device"),
                  subtitle: Text(device.address),
                  trailing: ElevatedButton(
                    child: const Text('CONNECT'),
                    onPressed: () {
                      // Implement connection logic here
                      _showConnectingDialog(device);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
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
                // Implement the connection logic here
                Navigator.of(context).pop();
                // This is where you would handle the actual connection
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Connecting to ${device.name ?? "Unknown device"}...'),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}