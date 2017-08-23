/*
This is an Arduino sketch designed to interface with an Arduino Uno, a Freetronics DLOCK shield, and an RDM630 RFID Module.
The main purpose of this is to interact with the DangerousThings xEM tag although this *should* work with other 125kHz tags.
The code isnt very optimised, but it does the job.

Author: James Campbell
Credits:
  Jonathan Oxer - for the original DLOCK sketch of which this is based on.
  ManiacBug - for the buffer code


Reference URLs:
http://wiki.seeed.cc/125Khz_RFID_module-UART/
P1's TX corresponds to Pin D2
P1's RX corresponds to Pin D3

P3's LED Pin is also hooked up to Pin D2 as a falling-edge filter.

https://www.freetronics.com.au/products/dlock-rfid-door-lock-shield
To purchase your own DLOCK shield but it isnt strictly necessary, I use it because of the 12v strike control


There is enough space to solder the RDM630 shield to a Freetronics Eleven (Uno Clone w/ prototyping space)


*/


#include <SoftwareSerial.h>
 
// Pin definitions
const int rfid_irq = 0;
const int rfid_tx_pin = 2;
const int rfid_rx_pin = 3;


#define strikePlate 9
#define ledPin 7

// Specify how long the strike plate should be held open.
#define unlockSeconds 2
 
// For communication with RFID module
SoftwareSerial rfid(rfid_tx_pin, rfid_rx_pin);
 
// Indicates that a reading is now ready for processing
volatile bool ready = false;
 
// Buffer to contain the reading from the module
uint8_t buffer[14];
uint8_t* buffer_at;
uint8_t* buffer_end = buffer + sizeof(buffer);
 
void rfid_read(void);
uint8_t rfid_get_next(void);

String allowedTags[] = {
  "",         /* This contains the value of tagId that is output to the Serial */
};

// List of names to associate with the matching tag IDs
char* tagName[] = {
  "INSERT NAME",       // Tag 1
};

// Check the number of tags defined
int numberOfTags = sizeof(allowedTags)/sizeof(allowedTags[0]);

int incomingByte = 0;    // To store incoming serial data



 
void setup(void)
{
  // Open serial connection to host PC to view output
  Serial.begin(38400);
  Serial.println("xEM RFID DLOCK");
 
  // Open software serial connection to RFID module
  pinMode(rfid_tx_pin,INPUT);
  rfid.begin(9600);
 
  // Listen for interrupt from RFID module
  attachInterrupt(rfid_irq,rfid_read,FALLING);
}
 
void loop(void)
{
  if ( ready )
  {
    // Convert the buffer into a 32-bit value
    uint32_t result = 0;
    
    // Skip the preamble
    ++buffer_at;
    
    // Accumulate the checksum, starting with the first value
    uint8_t checksum = rfid_get_next();
    
    // We are looking for 4 more values
    int i = 4;    
    while(i--)
    {
      // Grab the next value
      uint8_t value = rfid_get_next();
      
      // Add it into the result
      result <<= 8;
      result |= value;
      
      // Xor it into the checksum
      checksum ^= value;
    }
    
    // Pull out the checksum from the data
    uint8_t data_checksum = rfid_get_next();
    
    // Print the result
    Serial.print("TAG ID: ");
    Serial.print(result);
 
    if ( checksum == data_checksum ) {
      Serial.println(" OK");
      int tagId = findTag( result );
      if( tagId > 0 )
      {
        Serial.print("Authorized tag ID ");
        Serial.print(tagId);
        Serial.print(": unlocking for ");
        Serial.println(tagName[tagId - 1]);   // Get the name for this tag from the database
        unlock();                             // Fire the strike plate to open the lock
      } else {
        Serial.println("Tag not authorized");
      }
      Serial.println();     // Blank separator line in output

    } 
    else {
      Serial.println(" CHECKSUM FAILED");
    }
    // We're done processing, so there is no current value    
    ready = false;
  }
}
 
// Convert the next two chars in the stream into a byte and
// return that
uint8_t rfid_get_next(void)
{
  // sscanf needs a 2-byte space to put the result but we
  // only need one byte.
  uint16_t result;
 
  // Working space to assemble each byte
  static char byte_chars[3];
  
  // Pull out one byte from this position in the stream
  snprintf(byte_chars,3,"%c%c",buffer_at[0],buffer_at[1]);
  sscanf(byte_chars,"%x",&result);
  buffer_at += 2;
  
  return static_cast<uint8_t>(result);
}
 
void rfid_read(void)
{
  // Only read in values if there is not already a value waiting to be
  // processed
  if ( ! ready )
  {
    // Read characters into the buffer until it is full
    buffer_at = buffer;
    while ( buffer_at < buffer_end )
      *buffer_at++ = rfid.read();
      
    // Reset buffer pointer so it's easy to read out
    buffer_at = buffer;
  
    // Signal that the buffer has data ready
    ready = true;
  }
}

void unlock() {
  digitalWrite(ledPin, HIGH);
  digitalWrite(strikePlate, HIGH);
  delay(unlockSeconds * 1000);
  digitalWrite(strikePlate, LOW);
  digitalWrite(ledPin, LOW);
}

int findTag( uint32_t input) {
  for (int thisCard = 0; thisCard < numberOfTags; thisCard++) {
    // Check if the tag value matches this row in the tag database
    String input2 = (String) input;
    if(input2 == allowedTags[thisCard])
    {
      // The row in the database starts at 0, so add 1 to the result so
      // that the card ID starts from 1 instead (0 represents "no match")
      return(thisCard + 1);
    }
  }
  // If we don't find the tag return a tag ID of 0 to show there was no match
  return(0);
}