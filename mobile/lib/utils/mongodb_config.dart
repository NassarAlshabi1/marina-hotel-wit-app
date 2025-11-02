class MongoDBConfig {
  static const String connectionString = 
      "mongodb+srv://Nassar:<db_password>@cluster0.ai2ybe7.mongodb.net/?appName=Cluster0";
  
  static const String databaseName = "marina_hotel";
  
  static const String guestsCollection = "guests";
  static const String bookingsCollection = "bookings";
  static const String roomsCollection = "rooms";
  static const String paymentsCollection = "payments";
  
  static String getConnectionString(String password) {
    return connectionString.replaceAll('<db_password>', password);
  }
}
