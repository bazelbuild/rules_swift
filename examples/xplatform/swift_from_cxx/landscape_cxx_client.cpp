#include <iostream>

#include "examples/xplatform/swift_from_cxx/landscape-Swift.h"

// The Swift module "SwiftLandscape" is imported as the C++ namespace
// "SwiftLandscape".

SwiftLandscape::VolcanoStatus invertVolcanoStatus(
    SwiftLandscape::VolcanoStatus status) {
  switch (status) {
    case SwiftLandscape::VolcanoStatus::dormant:
      // Returns `VolcanoStatus.active` case.
      return SwiftLandscape::VolcanoStatus::active();
    case SwiftLandscape::VolcanoStatus::active:
      // Returns `VolcanoStatus.dormant` case.
      return SwiftLandscape::VolcanoStatus::dormant();
  }
}

void printLandmarkIdentifier(SwiftLandscape::LandmarkIdentifier identifier) {
  switch (identifier) {
    case SwiftLandscape::LandmarkIdentifier::name:
      std::cout << (std::string)identifier.getName() << std::endl;
      break;
    case SwiftLandscape::LandmarkIdentifier::id:
      std::cout << "unnamed landmark #" << identifier.getId() << std::endl;
      break;
  }
}

void structsAndClasses() {
  std::cout << "----- Swift structs and classes in C++ -----" << std::endl;

  // SwiftLandscape::MountainPeak is a Swift struct. But you must still use
  // init(), because Swift initializers are not the same as C++
  // constructors.
  SwiftLandscape::MountainPeak mount_everest =
      SwiftLandscape::MountainPeak::init("Mount Everest", 8848.0f);

  // You can call a Swift struct member function from C++.
  mount_everest.printDescription();

  // Swift arrays are mapped to swift::Array<T> in C++.
  auto peaks = swift::Array<SwiftLandscape::MountainPeak>::init();
  {
    SwiftLandscape::MountainPeak k2 =
        SwiftLandscape::MountainPeak::init("K2", 8611.0f);
    peaks.append(mount_everest);
    peaks.append(k2);
  }

  SwiftLandscape::MountainRange himalayas =
      SwiftLandscape::MountainRange::init(peaks);

  himalayas.printPeaks();
}

void simpleEnums() {
  std::cout << "----- Simple Swift enums -----" << std::endl;
  auto dormant = SwiftLandscape::VolcanoStatus::dormant();
  auto active = SwiftLandscape::VolcanoStatus::active();

  std::cout << "dormant has C++ int value: "
            << static_cast<int>(SwiftLandscape::VolcanoStatus::cases::dormant)
            << std::endl;
  std::cout << "active has C++ int value: "
            << static_cast<int>(SwiftLandscape::VolcanoStatus::cases::active)
            << std::endl;

  auto inverted = invertVolcanoStatus(dormant);
  std::cout << "inverted(dormant) == active? -> "
            << ((inverted == active) ? "true" : "false") << std::endl;
}

void enumsWithAssociatedTypes() {
  std::cout << "----- Swift enums with associated types -----" << std::endl;
  auto new_landmark_id = SwiftLandscape::LandmarkIdentifier::id(1234);
  printLandmarkIdentifier(new_landmark_id);

  auto new_landmark_name =
      SwiftLandscape::LandmarkIdentifier::name("Eiffel Tower");
  printLandmarkIdentifier(new_landmark_name);
}

int main(int argc, char* argv[]) {
  structsAndClasses();

  simpleEnums();

  enumsWithAssociatedTypes();

  return 0;
}
