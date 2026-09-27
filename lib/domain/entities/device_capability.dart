/// Capabilities that a device can support.
/// The UI uses these to determine which controls to display.
enum DeviceCapability {
  power('power', 'Power'),
  brightness('brightness', 'Brightness'),
  color('color', 'Color'),
  colorTemperature('colorTemperature', 'Color Temperature'),
  effect('effect', 'Effect'),
  speed('speed', 'Speed'),
  volume('volume', 'Volume'),
  channel('channel', 'Channel'),
  input('input', 'Input'),
  energy('energy', 'Energy'),
  temperature('temperature', 'Temperature'),
  humidity('humidity', 'Humidity'),
  motion('motion', 'Motion'),
  contact('contact', 'Contact');

  const DeviceCapability(this.id, this.label);
  final String id;
  final String label;
}