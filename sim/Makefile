# Makefile for Filecoin Economic Simulation
# Target: RTX 5080 (Blackwell, sm_100), CUDA 13.1

NVCC = nvcc
TARGET = filecoin_econ_sim
SRC = filecoin_econ_sim.cu

# Blackwell architecture
ARCH = -arch=sm_100

# Double precision, optimization
FLAGS = -O3 --use_fast_math -Xcompiler -Wall

# Results directory
RESULTS = ../results

all: $(TARGET)

$(TARGET): $(SRC)
	$(NVCC) $(ARCH) $(FLAGS) -o $(TARGET) $(SRC)

run: $(TARGET)
	mkdir -p $(RESULTS)
	./$(TARGET) $(RESULTS)

clean:
	rm -f $(TARGET)
	rm -f $(RESULTS)/*.csv

.PHONY: all run clean
