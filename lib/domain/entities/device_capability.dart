// SPDX-License-Identifier: Apache-2.0

/// Capabilities that a device can support.
/// The UI uses these to determine which controls to display.
enum DeviceCapability {
  power('power', 'Power'),
  brightness('brightness', 'Brightness'),
  color('color', 'Color'),
  colorTemperature('colorTemperature', 'Color Temperature'),
  effect('effect', 'Effect'),
  palette('palette', 'Palette'),
  speed('speed', 'Speed'),
  volume('volume', 'Volume'),
  channel('channel', 'Channel'),
  input('input', 'Input'),
  energy('energy', 'Energy'),
  temperature('temperature', 'Temperature'),
  humidity('humidity', 'Humidity'),
  motion('motion', 'Motion'),
  contact('contact', 'Contact'),
  gpio('gpio', 'GPIO'),
  relay('relay', 'Relay'),
  pwm('pwm', 'PWM'),
  fanSpeed('fanSpeed', 'Fan Speed'),
  fanMode('fanMode', 'Fan Mode'),
  display('display', 'Display'),
  text('text', 'Text'),
  graphics('graphics', 'Graphics'),
  animation('animation', 'Animation'),
  sensorReading('sensorReading', 'Sensor Reading'),
  threshold('threshold', 'Threshold'),
  state('state', 'State'),
  schedule('schedule', 'Schedule'),
  firmware('firmware', 'Firmware'),
  config('config', 'Configuration'),
  custom('custom', 'Custom Command'),
  // Phase 2: Cloud/infrastructure integrations
  wled('wled', 'WLED'),
  mqtt('mqtt', 'MQTT');

  const DeviceCapability(this.id, this.label);
  final String id;
  final String label;
}

/// Capabilities the built-in MR Star controller exposes over its GATT service
/// (FFF0 / write FFF3 / notify FFF4).
///
/// `effect` and `speed` map to the controller's native mode/speed packets
/// (`ProtocolEncoder.setEffect`/`setSpeed`) and match what
/// `StarLightBleAdapter` already advertises for MR Star devices. Colour
/// temperature is deliberately absent — the protocol has no
/// colour-temperature command.
const Set<DeviceCapability> kDefaultLightCapabilities = {
  DeviceCapability.power,
  DeviceCapability.brightness,
  DeviceCapability.color,
  DeviceCapability.effect,
  DeviceCapability.speed,
};
