#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    char *items[4096];
    size_t first, last;
    pthread_mutex_t mutex;
    pthread_cond_t ready;
} Queue;

static Queue updates = {.mutex = PTHREAD_MUTEX_INITIALIZER, .ready = PTHREAD_COND_INITIALIZER};
static Queue requests = {.mutex = PTHREAD_MUTEX_INITIALIZER, .ready = PTHREAD_COND_INITIALIZER};
static char *received;
static char *requested;

static void put(Queue *queue, const char *text) {
    pthread_mutex_lock(&queue->mutex);
    if (queue->last - queue->first == 4096) abort();
    queue->items[queue->last++ % 4096] = strdup(text);
    pthread_cond_signal(&queue->ready);
    pthread_mutex_unlock(&queue->mutex);
}

static char *take(Queue *queue) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += 2;
    pthread_mutex_lock(&queue->mutex);
    while (queue->first == queue->last) {
        if (pthread_cond_timedwait(&queue->ready, &queue->mutex, &deadline)) {
            pthread_mutex_unlock(&queue->mutex);
            return NULL;
        }
    }
    char *text = queue->items[queue->first++ % 4096];
    pthread_mutex_unlock(&queue->mutex);
    return text;
}

void tg_fake_push(const char *text) { put(&updates, text); }
const char *tg_fake_request(void) {
    free(requested);
    requested = take(&requests);
    return requested;
}
void *td_json_client_create(void) { return &updates; }
void td_json_client_send(void *client, const char *text) {
    (void)client;
    if (!strcmp(text, "{\"@type\":\"close\"}")) {
        put(&updates, "{\"@type\":\"authorizationStateClosed\"}");
    } else put(&requests, text);
}
const char *td_json_client_receive(void *client, double timeout) {
    (void)client;
    (void)timeout;
    free(received);
    received = take(&updates);
    return received;
}
const char *td_json_client_execute(void *client, const char *text) {
    (void)client;
    (void)text;
    return NULL;
}
void td_json_client_destroy(void *client) {
    (void)client;
    free(received);
    received = NULL;
    char *text;
    while (updates.first != updates.last) { text = take(&updates); free(text); }
    while (requests.first != requests.last) { text = take(&requests); free(text); }
}
int CreateDirectoryW(const unsigned short *path, void *attributes) {
    (void)path;
    (void)attributes;
    return 1;
}
