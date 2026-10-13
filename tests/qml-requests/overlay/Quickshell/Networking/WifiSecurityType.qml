pragma Singleton
import QtQuick

// Fake security values. Open and the password types (WpaPsk, Wpa2Psk, Sae) matter;
// Wpa2Eap and Owe stand for types that have no password flow.
QtObject { enum Kind { Open, Wpa2Psk, WpaPsk, Sae, Wpa2Eap, Owe } }
