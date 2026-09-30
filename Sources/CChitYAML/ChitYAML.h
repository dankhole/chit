#ifndef CHIT_YAML_H
#define CHIT_YAML_H
#include <stddef.h>
/* libyaml event numbers: stream 1/2, document 3/4, alias 5, scalar 6,
   sequence 7/8, mapping 9/10. Strings remain valid until the next event. */
typedef struct ChitYAMLParser ChitYAMLParser;
typedef struct {
    int type;
    const unsigned char *value;
    size_t length;
    const unsigned char *tag;
    int plain;
    size_t line, column;
} ChitYAMLEvent;
ChitYAMLParser *chit_yaml_open(const unsigned char *bytes, size_t length);
int chit_yaml_next(ChitYAMLParser *, ChitYAMLEvent *);
const char *chit_yaml_error(ChitYAMLParser *);
size_t chit_yaml_error_line(ChitYAMLParser *);
size_t chit_yaml_error_column(ChitYAMLParser *);
void chit_yaml_close(ChitYAMLParser *);
#endif
