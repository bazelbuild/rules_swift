typedef struct {
  int value;
} HermeticValue;

static inline HermeticValue hermetic_value(void) { return (HermeticValue){42}; }
