#!/usr/bin/env python3

import rclpy
from rclpy.node import Node
from std_msgs.msg import Float64MultiArray
import serial
import numpy as np
import time
import csv

class CncController(Node):
    def __init__(self):
        super().__init__('cnc_controller')

        # Define the serial ports and baud rate
        self.port1 = '/dev/ttyACM0'  # CNC 1
        self.port2 = '/dev/ttyACM1'  # CNC 2
        self.baudrate = 115200

        # Create serial objects for both CNC machines
        self.s1 = serial.Serial(self.port1, self.baudrate, timeout=1)
        self.s2 = serial.Serial(self.port2, self.baudrate, timeout=1)
        time.sleep(2)  # Wait for the connection to initialize

        # Parameters for sinusoidal and cosinusoidal wave
        self.amplitude = 10      # Amplitude of the wave
        self.frequency = 10      # Frequency of the wave
        self.num_points = 100    # Number of data points
        self.x_start = 0         # Start of x-axis
        self.x_end = 100         # End of x-axis

        # Generate X, Y, and Z coordinates (sinusoidal and cosinusoidal)
        self.x = np.linspace(self.x_start, self.x_end, self.num_points)  # Linearly spaced x values
        self.y = self.amplitude * np.sin(2 * np.pi * self.frequency * (self.x / self.x_end))  # Sine wave (y-axis)
        self.z = self.amplitude * np.cos(2 * np.pi * self.frequency * (self.x / self.x_end))  # Cosine wave (z-axis)

        # Prepare CSV file for logging data
        self.filename = 'CNC_Waveform_data.csv'
        self.fileID = open(self.filename, 'w', newline='')  # Open file for writing
        self.csv_writer = csv.writer(self.fileID)
        self.csv_writer.writerow(['X', 'Y', 'Z', 'CNC1_Response', 'CNC2_Response'])  # Write the headers

        # Create a publisher to send CNC position data
        self.publisher_ = self.create_publisher(Float64MultiArray, 'cnc_positions', 10)

        # Start sending commands
        self.send_commands()

    def send_commands(self):
        for i in range(self.num_points):
            # Prepare G-code commands for both CNC machines
            command1 = f'G001 X{x[i]:.2f} Y{y[i]:.2f} Z{z[i]:.2f} F500\n'  # CNC 1
            command2 = f'G001 X{x[i]:.2f} Y{-y[i]:.2f} Z{-z[i]:.2f} F500\n'  # CNC 2 (opposite direction)

            # Send the commands to both CNCs
            self.s1.write(command1.encode())  # Send G-code to CNC 1
            self.s2.write(command2.encode())  # Send G-code to CNC 2

            # Wait for responses from both CNCs
            response1 = self.s1.readline().decode('utf-8').strip()
            response2 = self.s2.readline().decode('utf-8').strip()

            # Display responses for debugging
            self.get_logger().info(f'Response from CNC 1: {response1}')
            self.get_logger().info(f'Response from CNC 2: {response2}')

            # Extract real-time position values from CNC responses
            responseData1 = list(map(float, response1.split(','))) if response1 else [0, 0, 0]  # Parse response from CNC 1
            responseData2 = list(map(float, response2.split(','))) if response2 else [0, 0, 0]  # Parse response from CNC 2

            # Collect real-time feedback (for example, position Y from CNC)
            real_time_y1 = responseData1[1] if len(responseData1) >= 3 else float('nan')
            real_time_y2 = responseData2[1] if len(responseData2) >= 3 else float('nan')

            # Log the real-time data into the CSV file
            self.csv_writer.writerow([self.x[i], self.y[i], self.z[i], real_time_y1, real_time_y2])

            # Publish data to the ROS topic
            msg = Float64MultiArray()
            msg.data = [self.x[i], self.y[i], self.z[i], real_time_y1, real_time_y2]
            self.publisher_.publish(msg)

            # Pause briefly to allow CNCs to execute the command
            time.sleep(0.1)

        # Clean up
        self.fileID.close()
        self.s1.close()
        self.s2.close()
        self.get_logger().info(f'Data saved to {self.filename}')

def main(args=None):
    rclpy.init(args=args)
    cnc_controller = CncController()
    rclpy.spin(cnc_controller)
    cnc_controller.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
