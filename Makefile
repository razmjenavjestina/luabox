DEBUG=debug
RELEASE=release
CORES=4
BUILD_DIR=bld
TEST_DIR=bin
PREFIX=out
INSTALL_PREFIX = $(abspath $(PREFIX))
TARGET=$(DEBUG)

all:
	@echo 'usage: ...'

$(DEBUG):
	@sh -c "mkdir -p $(BUILD_DIR)/$(DEBUG) && \
                cd $(BUILD_DIR)/$(DEBUG) && \
                cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
                      -DCMAKE_INSTALL_PREFIX=$(INSTALL_PREFIX)\
                      -DCMAKE_BUILD_TYPE=$(DEBUG) ../.."

$(RELEASE):
	@sh -c "mkdir -p $(BUILD_DIR)/$(RELEASE) && \
                cd $(BUILD_DIR)/$(RELEASE) && \
                cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
                      -DCMAKE_INSTALL_PREFIX=$(INSTALL_PREFIX)\
                      -DCMAKE_BUILD_TYPE=$(RELEASE) ../.."

build: $(TARGET)
	@sh -c "cd $(BUILD_DIR)/$(TARGET) && make -j$(CORES)"

install: build
	@sh -c "cd $(BUILD_DIR)/$(TARGET) && make install"

clean:
	@rm -rf $(BUILD_DIR)
	@rm -rf $(TEST_DIR)
	@rm -rf $(INSTALL_PREFIX)

.PHONY: build install clean $(DEBUG) $(RELEASE)
