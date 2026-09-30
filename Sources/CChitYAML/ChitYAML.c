#include "ChitYAML.h"
#include "yaml.h"
#include <stdlib.h>
#include <string.h>
struct ChitYAMLParser {
    yaml_parser_t parser;
    yaml_event_t event;
    int has_event;
};
ChitYAMLParser *chit_yaml_open(const unsigned char *bytes, size_t length) {
    ChitYAMLParser *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    if (!yaml_parser_initialize(&p->parser)) { free(p); return NULL; }
    yaml_parser_set_input_string(&p->parser, bytes, length);
    return p;
}
int chit_yaml_next(ChitYAMLParser *p, ChitYAMLEvent *out) {
    if (p->has_event) { yaml_event_delete(&p->event); p->has_event = 0; }
    memset(out, 0, sizeof(*out));
    if (!yaml_parser_parse(&p->parser, &p->event)) return 0;
    p->has_event = 1;
    out->type = p->event.type;
    out->line = p->event.start_mark.line + 1;
    out->column = p->event.start_mark.column + 1;
    switch (p->event.type) {
        case YAML_SCALAR_EVENT:
            out->value = p->event.data.scalar.value;
            out->length = p->event.data.scalar.length;
            out->tag = p->event.data.scalar.tag;
            out->plain = p->event.data.scalar.style == YAML_PLAIN_SCALAR_STYLE;
            break;
        case YAML_SEQUENCE_START_EVENT: out->tag = p->event.data.sequence_start.tag; break;
        case YAML_MAPPING_START_EVENT: out->tag = p->event.data.mapping_start.tag; break;
        default: break;
    }
    return 1;
}
const char *chit_yaml_error(ChitYAMLParser *p) { return p->parser.problem ? p->parser.problem : "YAML parser failed"; }
size_t chit_yaml_error_line(ChitYAMLParser *p) { return p->parser.problem_mark.line + 1; }
size_t chit_yaml_error_column(ChitYAMLParser *p) { return p->parser.problem_mark.column + 1; }
void chit_yaml_close(ChitYAMLParser *p) {
    if (!p) return;
    if (p->has_event) yaml_event_delete(&p->event);
    yaml_parser_delete(&p->parser);
    free(p);
}
