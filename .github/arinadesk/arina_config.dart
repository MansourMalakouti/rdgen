// ArinaDesk support-portal defaults.
// Edit these values to point the client at another Zammad helpdesk.
// The user can still change the address in the app's support settings.

/// Base address of the Zammad helpdesk (the public login page, no secrets).
const String kArinaZammadUrl = 'https://help.arinet.ir';

/// Zammad group that new tickets are created in.
const String kArinaZammadGroup = 'پشتیبانی و نصب نرم افزار';

/// Names of the custom Zammad ticket fields (Admin > System > Objects > Ticket).
/// Set a name to '' to stop sending that field (and hide its input).
///   name      = requester name, asked in the form (remembered per computer)
///   phone     = contact phone, asked in the form (remembered per computer)
///   arinadesk = filled automatically with this computer's ArinaDesk ID
const String kArinaFieldName = 'name';
const String kArinaFieldPhone = 'phone';
const String kArinaFieldDeviceId = 'arinadesk';

/// Extra ticket fields sent with every new ticket (for required custom
/// fields of your Zammad), e.g. {'my_field': 'value'}. Empty by default.
const Map<String, Object> kArinaZammadExtraFields = {};

/// How often (minutes) the app checks the tickets created from this computer.
const int kArinaPollMinutes = 5;
