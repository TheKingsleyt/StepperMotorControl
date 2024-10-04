% Define the serial ports and baud rate
port1 = 'COM12';  % CNC 1
port2 = 'COM14';  % CNC 2
baudrate = 115200;

% Create serial objects for both CNC machines
s1 = serialport(port1, baudrate);
s2 = serialport(port2, baudrate);
configureTerminator(s1, 'LF');
configureTerminator(s2, 'LF');

% Parameters for sinusoidal and cosinusoidal wave
amplitude = 10;      % Amplitude of the wave
frequency = 10;      % Frequency of the wave
num_points = 100;    % Number of data points
x_start = 0;         % Start of x-axis
x_end = 100;         % End of x-axis

% Generate X, Y, and Z coordinates (sinusoidal and cosinusoidal)
x = linspace(x_start, x_end, num_points);  % Linearly spaced x values
y = amplitude * sin(2 * pi * frequency * (x / x_end));  % Sine wave (y-axis)
z = amplitude * cos(2 * pi * frequency * (x / x_end));  % Cosine wave (z-axis)

% Save the data to a new CSV file for training
filename = 'Waveform_data.csv';
fileID = fopen(filename, 'w');  % Open file for writing
fprintf(fileID, 'X,Y,Z,CNC1_Response,CNC2_Response\n');  % Write the headers

% Prepare for CNN training
images = zeros(100, 100, 1, num_points);  % Placeholder for image data (e.g., 100x100 grayscale images)
positions = zeros(num_points, 3);          % Placeholder for position data (X, Y, Z)

% Create animated lines for real-time plotting
figure;
h1 = animatedline('Color', 'r', 'LineWidth', 1.5);  % Red line for CNC 1
h2 = animatedline('Color', 'b', 'LineWidth', 1.5);  % Blue line for CNC 2

xlabel('X Axis');
ylabel('Amplitude');
title('Real-Time CNC Position Tracking');
legend({'CNC 1', 'CNC 2'}, 'Location', 'best');
grid on;

% Set axis limits for real-time plot
xlim([x_start x_end]);
ylim([-amplitude-5 amplitude+5]);

% Send G-code commands to both CNC machines and write data points to CSV file
for i = 1:num_points
    % Prepare G-code commands for both CNC machines
    command1 = sprintf('G001 X%.2f Y%.2f Z%.2f F500', x(i), y(i), z(i));  % CNC 1
    command2 = sprintf('G001 X%.2f Y%.2f Z%.2f F500', x(i), -y(i), -z(i));  % CNC 2 (opposite direction)

    % Send the commands to both CNCs
    writeline(s1, command1);  % Send G-code to CNC 1
    writeline(s2, command2);  % Send G-code to CNC 2

    % Wait for responses from both CNCs
    response1 = readline(s1);
    response2 = readline(s2);
    
    % Display responses for debugging
    disp(['Response from CNC 1: ', response1]);
    disp(['Response from CNC 2: ', response2]);

    % Extract real-time position values from CNC responses
    responseData1 = str2double(split(response1, ','));  % Split response to get individual values
    responseData2 = str2double(split(response2, ','));

    % Collect position feedback
    if length(responseData1) < 3
        disp('Error: CNC 1 response does not contain enough data.');
        real_time_y1 = NaN;  % Set to NaN if not valid
    else
        real_time_y1 = responseData1(2);  % Assume the second element is the Y position
    end

    if length(responseData2) < 3
        disp('Error: CNC 2 response does not contain enough data.');
        real_time_y2 = NaN;  % Set to NaN if not valid
    else
        real_time_y2 = responseData2(2);  % Assume the second element is the Y position
    end

    % Update real-time plot with CNC position data
    addpoints(h1, x(i), real_time_y1);  % Add points to animated line for CNC 1
    addpoints(h2, x(i), real_time_y2);  % Add points to animated line for CNC 2

    % Pause briefly to allow for real-time plotting
    drawnow;  % Update the plot

    % Log the real-time data into the CSV file
    fprintf(fileID, '%.2f,%.2f,%.2f,%.2f,%.2f\n', x(i), y(i), z(i), real_time_y1, real_time_y2);
    
    % Collect image data (this is a placeholder; replace with actual image capture code)
    images(:, :, 1, i) = rand(100, 100);  % Placeholder for capturing image data
    positions(i, :) = [x(i), y(i), z(i)];   % Collect positions

    % Pause briefly to allow CNCs to execute the command
    pause(0.1);
end

% Close the file and serial ports
fclose(fileID);
delete(s1);
delete(s2);
clear s1 s2;

% Confirm the data has been saved
disp(['Data saved to ', filename]);

% Prepare the data for CNN training
% Assume images is a 4D array of image data, labels are generated from the position data
labels = categorical(1:num_points);  % Dummy labels; replace with your actual labels
positions = (positions - mean(positions, 1)) ./ std(positions, 0, 1);  % Standardize positions

% Split data into training (70%) and testing (30%)
numImages = num_points;
idx = randperm(numImages);
numTrain = round(0.7 * numImages);

trainImages = images(:, :, :, idx(1:numTrain));
trainLabels = labels(idx(1:numTrain));
trainPositions = positions(idx(1:numTrain), :);

testImages = images(:, :, :, idx(numTrain+1:end));
testLabels = labels(idx(numTrain+1:end));
testPositions = positions(idx(numTrain+1:end), :);

% Define the CNN architecture
layers = [
    imageInputLayer([size(images, 1) size(images, 2) 1])  % Adjust input size
    convolution2dLayer(3, 8, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    maxPooling2dLayer(2, 'Stride', 2)

    convolution2dLayer(3, 16, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    maxPooling2dLayer(2, 'Stride', 2)

    convolution2dLayer(3, 32, 'Padding', 'same')
    batchNormalizationLayer
    reluLayer
    maxPooling2dLayer(2, 'Stride', 2)

    fullyConnectedLayer(128)  % Fully connected layer before output
    reluLayer
    dropoutLayer(0.5)  % Dropout layer to prevent overfitting
    fullyConnectedLayer(numel(unique(trainLabels)))  % Number of classes
    softmaxLayer
    classificationLayer
];

% Set training options with hyperparameters
options = trainingOptions('sgdm', ...
    'MaxEpochs', 50, ...  % Increase epochs for better training
    'MiniBatchSize', 32, ...  % Batch size to improve training speed
    'InitialLearnRate', 0.001, ...  % Learning rate
    'Shuffle', 'every-epoch', ...
    'ValidationData', {testImages, testLabels}, ...
    'Verbose', false, ...
    'Plots', 'training-progress');

% Train the network
net = trainNetwork(trainImages, trainLabels, layers, options);

% Evaluate the trained network
predictedLabels = classify(net, testImages);
accuracy = sum(predictedLabels == testLabels) / numel(testLabels);
disp(['Test Accuracy: ', num2str(accuracy * 100), '%']);

% Confusion matrix
figure;
confusionchart(testLabels, predictedLabels);
title('Confusion Matrix');

% Optional: Save the trained model
save('trainedCNN.mat', 'net');

% Position Feedback Evaluation (Optional)
% To evaluate how well the model predicts based on positions
positionPredictedLabels = classify(net, testImages);  % or other model if combined
positionAccuracy = sum(positionPredictedLabels == testLabels) / numel(testLabels);
disp(['Position Feedback Accuracy: ', num2str(positionAccuracy * 100), '%']);
