package com.hmdp.service.impl;

import com.hmdp.dto.LoginFormDTO;
import com.hmdp.dto.Result;
import com.hmdp.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.concurrent.TimeUnit;

import static com.hmdp.utils.RedisConstants.LOGIN_CODE_KEY;
import static com.hmdp.utils.RedisConstants.LOGIN_CODE_TTL;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UserServiceValidationTest {

    @Mock
    private UserMapper userMapper;
    @Mock
    private StringRedisTemplate redisTemplate;
    @Mock
    private ValueOperations<String, String> valueOperations;

    private UserServiceImpl service;

    @BeforeEach
    void setUp() {
        service = new UserServiceImpl(userMapper);
        ReflectionTestUtils.setField(service, "stringRedisTemplate", redisTemplate);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "1380013800", "138001380000", "23800138000", "1380013800a"})
    void sendCodeRejectsInvalidPhoneWithoutAccessingStorage(String phone) {
        Result result = service.sendCode(phone, null);

        assertFalse(result.getSuccess());
        assertEquals("手机号格式错误", result.getErrorMsg());
        verifyNoInteractions(redisTemplate, userMapper);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "1380013800", "138001380000", "23800138000", "1380013800a"})
    void loginRejectsInvalidPhoneWithoutAccessingStorage(String phone) {
        LoginFormDTO form = new LoginFormDTO();
        form.setPhone(phone);
        form.setCode("123456");

        Result result = service.login(form, null);

        assertFalse(result.getSuccess());
        assertEquals("手机号格式错误", result.getErrorMsg());
        verifyNoInteractions(redisTemplate, userMapper);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"654321"})
    void loginRejectsMissingOrIncorrectCachedCode(String cachedCode) {
        LoginFormDTO form = new LoginFormDTO();
        form.setPhone("13800138000");
        form.setCode("123456");
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get(LOGIN_CODE_KEY + form.getPhone())).thenReturn(cachedCode);

        Result result = service.login(form, null);

        assertFalse(result.getSuccess());
        assertEquals("验证码错误", result.getErrorMsg());
        verifyNoInteractions(userMapper);
        verify(redisTemplate).opsForValue();
        verify(valueOperations).get(LOGIN_CODE_KEY + form.getPhone());
        verifyNoMoreInteractions(redisTemplate, valueOperations);
    }

    @Test
    void sendCodeStoresSixDigitsWithExpiration() {
        String phone = "13800138000";
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);

        Result result = service.sendCode(phone, null);

        assertTrue(result.getSuccess());
        assertNull(result.getData());
        ArgumentCaptor<String> code = ArgumentCaptor.forClass(String.class);
        verify(valueOperations).set(eq(LOGIN_CODE_KEY + phone), code.capture(),
                eq(LOGIN_CODE_TTL), eq(TimeUnit.MINUTES));
        assertTrue(code.getValue().matches("[0-9]{6}"));
        verifyNoInteractions(userMapper);
    }
}
