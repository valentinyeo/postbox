#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

static int shim_vsnprintf(char *buffer, size_t count, const char *format, va_list args) {
    return vsnprintf(buffer, count, format, args);
}

static int shim_vsnwprintf(wchar_t *buffer, size_t count, const wchar_t *format, va_list args) {
    return vswprintf(buffer, count, format, args);
}

int _vsnprintf(char *buffer, size_t count, const char *format, va_list args);
int _vsnwprintf(wchar_t *buffer, size_t count, const wchar_t *format, va_list args);

int _vsnprintf(char *buffer, size_t count, const char *format, va_list args) {
    return shim_vsnprintf(buffer, count, format, args);
}

int _vsnwprintf(wchar_t *buffer, size_t count, const wchar_t *format, va_list args) {
    return shim_vsnwprintf(buffer, count, format, args);
}

void *__imp__vsnprintf = (void *)&_vsnprintf;
void *__imp__vsnwprintf = (void *)&_vsnwprintf;

static long shim_timezone = 0;
void *__imp__timezone = (void *)&shim_timezone;
