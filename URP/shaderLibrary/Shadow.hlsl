#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"

#if defined(_DIRECTIONAL_PCF3)
#define DIRECTIONAL_FILTER_SAMPLES 4
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
#define DIRECTIONAL_FILTER_SAMPLES 9
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
#define DIRECTIONAL_FILTER_SAMPLES 16
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#if defined(_OTHER_PCF3)
#define OTHER_FILTER_SAMPLES 4
#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_OTHER_PCF5)
#define OTHER_FILTER_SAMPLES 9
#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_OTHER_PCF7)
#define OTHER_FILTER_SAMPLES 16
#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_SHADOWED_OTHER_LIGHT_COUNT 16
#define MAX_CASCADE_COUNT 4

TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
TEXTURE2D_SHADOW(_OtherShadowAtlas);
	#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);

CBUFFER_START(_CustomShadows)
	int _CascadeCount;
	float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
	float4 _CascadeData[MAX_CASCADE_COUNT];
	float4x4 _DirectionalShadowMatrix[MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
	float4x4 _OtherShadowMatrices[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _OtherShadowTiles[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _ShadowDistanceFade;
	float4 _ShadowAtlasSize;
CBUFFER_END

struct DirectionalShadowData {
	float strength;
	int tileIndex;
	float normalBias;
	int shadowMaskChannel;
};

struct OtherShadowData {
	bool isPoint;
	float strength;
	int tileIndex;
	int shadowMaskChannel;
	float3 lightPosition;
	float3 lightDirection;
	float3 spotDirection;
};


struct ShadowMask {
	bool always;
	bool distance;
	float4 shadows;	//�����õ��ļ����Ӱ
};

struct ShadowData {
	int cascadeIndex;
	float strength;
	float cascadeBlend;
	ShadowMask shadowMask;
};

float FadeShadowStrength(float distance, float scale, float fade) {
	return saturate((1.0f - distance * scale) * fade);
}

ShadowData getShadowData(Surface surface) {

	ShadowData shadowData;
	shadowData.cascadeBlend = 1.0f;
	shadowData.shadowMask.always = false;
	shadowData.shadowMask.distance = false;
	shadowData.shadowMask.shadows = 1.0f;
	
	int i;
	for (i = 0; i < _CascadeCount; i++) {
		float4 sphere = _CascadeCullingSpheres[i];
		float distanceSqr = DistanceSquared(surface.position, sphere.xyz);
		if (distanceSqr < sphere.w) {

			float fade = FadeShadowStrength(distanceSqr, _CascadeData[i].x, _ShadowDistanceFade.z);

			//shadowData.strength = surface.depth < _ShadowDistance ? 1.0f : 0.0f;
			//��Ϊ���ڶ�̬������������ʱ��ȡ�������farplane��maxDistance�Ľ�Сֵ
			shadowData.strength = FadeShadowStrength(surface.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y);
			if (i + 1 == _CascadeCount) {
				//��������������ʱ�䵭
				shadowData.strength *= fade;
			}
			else {
				shadowData.cascadeBlend = fade;
			}

			break;
		}
	}

	//�����������������������0��������û��ƽ�й⵫�з�ƽ�й�ʱ����������ʹΪ0��ȫ�ֹ���ǿ��Ҳ��Ϊ0����ƽ�й���Ӱ��Ȼ�ɼ������Ͳ�������Ӱ��
	if (i == _CascadeCount && _CascadeCount > 0) {
		shadowData.strength = 0.0f;
	}
#if defined(_CASCADE_BLEND_DITHER)
	else if (shadowData.cascadeBlend < surface.dither) {
		i += 1;
	}
#endif

	//�����Ӳ��Ӱ���Ƕ�������ô�Ͳ�����������Ĺ���
	#if !defined(_CASCADE_BLEND_SOFT)
		shadowData.cascadeBlend = 1.0;
	#endif

	shadowData.cascadeIndex = i;

	return shadowData;
}

float SampleDirectionalShadowAtlas(float3 positionSTS) {
	return SAMPLE_TEXTURE2D_SHADOW(
		_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS
	);
}

float FilterDirectionalShadow(float3 positionSTS) {
#if defined(DIRECTIONAL_FILTER_SETUP)
	float weights[DIRECTIONAL_FILTER_SAMPLES];
	float2 positions[DIRECTIONAL_FILTER_SAMPLES];
	float4 size = _ShadowAtlasSize.yyxx;
	DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
	float shadow = 0;
	for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++) {
		shadow += weights[i] * SampleDirectionalShadowAtlas(float3(positions[i].xy, positionSTS.z));
	}
	return shadow;
#else
	return SampleDirectionalShadowAtlas(positionSTS);	//Ĭ�ϲ���Ϊ���Բ�ֵ2x2
#endif
}

float getCascadeShadow(DirectionalShadowData data, Surface surfaceWS, ShadowData global) {

	float3 normalBias = surfaceWS.interpolatedNormal * data.normalBias * _CascadeData[global.cascadeIndex].y;

	float3 positionSTS = mul(
		_DirectionalShadowMatrix[data.tileIndex],
		float4(surfaceWS.position + normalBias, 1.0)
	).xyz;
	float shadow = FilterDirectionalShadow(positionSTS);

	//������һ�ȵ������������������ϣ�ʹ�����������ı߽粻����
	if (global.cascadeBlend < 1.0f) {
		normalBias = surfaceWS.interpolatedNormal * data.normalBias * _CascadeData[global.cascadeIndex + 1].y;
		positionSTS = mul(
			_DirectionalShadowMatrix[data.tileIndex + 1],
			float4(surfaceWS.position + normalBias, 1.0)
		).xyz;
		shadow = lerp(FilterDirectionalShadow(positionSTS), shadow, global.cascadeBlend);
	}

	return shadow;

}

float getBakedShadow(ShadowMask mask, int channel) {
	if (mask.always || mask.distance) {
		if (channel >= 0) {		//��ʹ��������Ӱ���֣����������Դ����Ӱ����Ϊ��ʹ����Ӱ���֣���ô��Ϊ-1
			return mask.shadows[channel];
		}
	}
	return 1.0f;
}

//����Ӱǿ��Ϊ0�򳬳�ʵʱ��Ӱ��Χʱ������ȡ�þ�̬��Ӱ��
float getBakedShadow(ShadowMask mask, float strength, int channel) {
	return lerp(1.0f, getBakedShadow(mask, channel), strength);	//��ǿ��Ӱ��
}

float mixBakedAndRealTimeShadows(ShadowData global, float shadow, float strength, int maskChannel) {

	float baked = getBakedShadow(global.shadowMask, maskChannel);
	if (global.shadowMask.always) {
		shadow = lerp(1.0f, shadow, global.strength);	//Զ��Ӱ��,ʵʱ��Ӱ
		shadow = min(shadow, baked);	//ԽС��˵����ӰԽǿ�������õ�����Ӱ���ǿ��Ӧ��rgb��С��
		return lerp(1.0f, shadow, strength);	//��ǿ��Ӱ��
	}else if (global.shadowMask.distance) {
		shadow = lerp(baked, shadow, global.strength);	//Զ��Ӱ��
		return lerp(1.0f, shadow, strength);	//��ǿ��Ӱ��
	}
	//��light.hlsl�е�GetDirectionalShadowData�����Ļ��strengthʱ�ж�Զ���Ƶ������Ϊ������if����Ҫ��Ҫ����Զ��Ӱ�����Ӱǿ�ȶ���Ӱ���в�ֵ��
	return lerp(1.0, shadow, strength * global.strength); 
}

//data.strength������յ���Ӱǿ�ȣ�global.strength����Զ��Ӱ�����Ӱǿ�ȡ�
float GetDirectionalShadowAttenuation(DirectionalShadowData data, Surface surfaceWS, ShadowData global) {

#if defined(_FORWARDPIPELINE)
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
#endif

	if (data.strength * global.strength <= 0.0) {
		//û��ʵʱ��Ӱʱ��ֻ���þ�̬��Ӱ
		return getBakedShadow(global.shadowMask, data.strength, data.shadowMaskChannel);
	}

	//����ʵʱ��Ӱʱ�����ʵʱ��Ӱ�;�̬��Ӱ
	float shadow = getCascadeShadow(data, surfaceWS, global);
	return shadow;
	return mixBakedAndRealTimeShadows(global, shadow, data.strength, data.shadowMaskChannel);

}

float sampleOtherShadowAtlas(float3 positionSTS, float3 bounds) {
	positionSTS.xy = clamp(positionSTS.xy, bounds.xy, bounds.xy + bounds.z);	//ͨ��positionSTS������UV��ʹ�䲻�ᳬ������
	return SAMPLE_TEXTURE2D_SHADOW(_OtherShadowAtlas, SHADOW_SAMPLER, positionSTS);
}

float FilterOtherShadow(float3 positionSTS, float3 bounds) {
#if defined(OTHER_FILTER_SETUP)
	real weights[OTHER_FILTER_SAMPLES];
	real2 positions[OTHER_FILTER_SAMPLES];
	float4 size = _ShadowAtlasSize.wwzz;
	OTHER_FILTER_SETUP(size, positionSTS.xy, weights, positions);
	float shadow = 0;
	for (int i = 0; i < OTHER_FILTER_SAMPLES; i++) {
		shadow += weights[i] * sampleOtherShadowAtlas(float3(positions[i].xy, positionSTS.z), bounds);
	}
	return shadow;
#else
	return sampleOtherShadowAtlas(positionSTS, bounds);
#endif
}

static const float3 pointShadowPlanes[6] = {
	float3(-1.0, 0.0, 0.0),
	float3(1.0, 0.0, 0.0),
	float3(0.0, -1.0, 0.0),
	float3(0.0, 1.0, 0.0),
	float3(0.0, 0.0, -1.0),
	float3(0.0, 0.0, 1.0)
};

float getOtherShadow(OtherShadowData other, Surface surface, ShadowData global) {
	

	float tileIndex = other.tileIndex;
	float3 lightPlane = other.spotDirection;

	if (other.isPoint) {
		float faceOffset = CubeMapFaceID(-other.lightDirection);	//���ݷ����������Ӧ��Ӱ��ͼ���������
		tileIndex += faceOffset;
		lightPlane = pointShadowPlanes[faceOffset];
	}

	float4 tileData = _OtherShadowTiles[tileIndex];

	float3 surfaceToLight = other.lightPosition - surface.position;
	float distanceToLightPlane = dot(surfaceToLight, lightPlane);	//�͹��߷�����е�ˣ����㵥λ�����µ����ش�С��cos����,�Դ˶�normalBias�������š�

	float3 normalBias = surface.interpolatedNormal * distanceToLightPlane * tileData.w;
	float4 positionSTS = mul(
		_OtherShadowMatrices[tileIndex],
		float4(surface.position + normalBias, 1.0)	//����normalBias��positionSTS���ܻᳬ������ƽ�棬�����ں�������clamp
	);
	return FilterOtherShadow(positionSTS.xyz / positionSTS.w, tileData.xyz);

}

float getOtherShadowAttenuation(OtherShadowData other, Surface surface, ShadowData global) {

#if defined(_FORWARDPIPELINE)
	#if !defined(_RECEIVE_SHADOWS)
	return 1.0;
	#endif
#endif

	float shadow;
	if (other.strength * global.strength <= 0.0f) {
		shadow = getBakedShadow(global.shadowMask, other.strength, other.shadowMaskChannel);
	}
	else {
		shadow = getOtherShadow(other, surface, global);
		shadow = mixBakedAndRealTimeShadows(global, shadow, other.strength, other.shadowMaskChannel);
	}

	return shadow;

}

#endif