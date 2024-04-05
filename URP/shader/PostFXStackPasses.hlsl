#ifndef CUSTOM_POST_FX_PASSES_INCLUDED
#define CUSTOM_POST_FX_PASSES_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

TEXTURE2D(_PostFXSource);
TEXTURE2D(_PostFXSource2);
TEXTURE2D(_ColorGradingLUT);

half4 _PostFXSource_TexelSize;

float4 getSource(float2 screenUV) {
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource, sampler_linear_clamp, screenUV, 0);
}

float4 getSource2(float2 screenUV) {
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource2, sampler_linear_clamp, screenUV, 0);
}

float4 getSourceBicubic(float2 screenUV) {
	return SampleTexture2DBicubic(
		TEXTURE2D_ARGS(_PostFXSource, sampler_linear_clamp), screenUV,
		_PostFXSource_TexelSize.zwxy, 1.0, 0.0
	);
}

struct Varyings {
	float4 vertex : SV_POSITION;
	float2 uv : VAR_SCREEN_UV;
};

Varyings DefaultPassVertex(uint vertexID : SV_VertexID) {

	Varyings o;

	o.vertex = float4(
		vertexID <= 1 ? -1.0f : 3.0f,
		vertexID == 0 ? 3.0f : -1.0f,
		0.0f, 1.0f
		);
	o.uv = float2(
		vertexID <= 1 ? 0.0f : 2.0f,
		vertexID == 0 ? 2.0f : 0.0f
		);

	if (_ProjectionParams.x < 0.0f) {
		o.uv.y = 1.0f - o.uv.y;
	}

	return o;
}

float4 CopyPassFragment(Varyings i) : SV_TARGET{
	return getSource(i.uv);
}

float4 BloomHorizontalPassFragment(Varyings input) : SV_TARGET{

	float3 color = 0.0f;

	float offsets[] = { -4.0f, -3.0f, -2.0f, -1.0f, 0.0f, 1.0f, 2.0f, 3.0f, 4.0f };
	float weights[] = {
		0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703,
		0.19459459, 0.12162162, 0.05405405, 0.01621622
	};
	
	for (int i = 0; i < 9; i++) {
		float offset = offsets[i] * _PostFXSource_TexelSize.x;
		color += getSource(input.uv + float2(offset, 0.0f)).rgb * weights[i];
	}

	return float4(color, 1.0f);

}

float4 BloomVerticalPassFragment(Varyings input) : SV_TARGET{
	float3 color = 0.0;
	float offsets[] = {
		-3.23076923, -1.38461538, 0.0, 1.38461538, 3.23076923
	};
	float weights[] = {
		0.07027027, 0.31621622, 0.22702703, 0.31621622, 0.07027027
	};
	for (int i = 0; i < 5; i++) {
		float offset = offsets[i] * _PostFXSource_TexelSize.y;
		color += getSource(input.uv + float2(0.0, offset)).rgb * weights[i];
	}
	return float4(color, 1.0);
}

bool _BloomBicubicUpsampling;
float _BloomIntensity;

float4 BloomAddPassFragment(Varyings i) : SV_TARGET{
	float3 lowRes;
	if (_BloomBicubicUpsampling) {
		lowRes = getSourceBicubic(i.uv).rgb;
	}
	else {
		lowRes = getSource(i.uv).rgb;
	}
	float4 highRes = getSource2(i.uv);	//��˹ģ��֮ǰ����һ����mipmap
	return float4(lowRes * _BloomIntensity + highRes.rgb, highRes.a);
}

float4 BloomScatterPassFragment(Varyings i) : SV_TARGET{
	float3 lowRes;
	if (_BloomBicubicUpsampling) {
		lowRes = getSourceBicubic(i.uv).rgb;
	}
	else {
		lowRes = getSource(i.uv).rgb;
	}
	float4 highRes = getSource2(i.uv);	//��˹ģ��֮ǰ����һ����mipmap
	return float4(lerp(highRes.rgb, lowRes, _BloomIntensity), highRes.a);
}

float4 _BloomThreshould;

float3 ApplyBloomThreshould(float3 color) {
	float3 brightness = Max3(color.r, color.g, color.b);	//�������
	float soft = brightness + _BloomThreshould.y;
	soft = clamp(soft, 0.0f, _BloomThreshould.z);	//��soft����
	soft = soft * soft * _BloomThreshould.w;
	float contribution = max(soft, brightness - _BloomThreshould.x) / max(brightness, 0.00001f);
	return color * contribution;
}

float4 BloomScatterFinalPassFragment(Varyings i) : SV_TARGET{
	float3 lowRes;
	if (_BloomBicubicUpsampling) {
		lowRes = getSourceBicubic(i.uv).rgb;
	}
	else {
		lowRes = getSource(i.uv).rgb;
	}
	float4 highRes = getSource2(i.uv);	//��˹ģ��֮ǰ����һ����mipmap
	lowRes += highRes.rgb - ApplyBloomThreshould(highRes);
	return float4(lerp(highRes.rgb, lowRes, _BloomIntensity), highRes.a);
}

float4 BloomPrefilterPassFragment(Varyings i) : SV_TARGET{
	float3 color = ApplyBloomThreshould(getSource(i.uv).rgb);
	return float4(color, 1.0f);
}

float4 BloomPrefilterFirefliesPassFragment(Varyings input) : SV_TARGET{
	float3 color = 0.0f;
	float weightSum = 0.0f;
	float2 offsets[] = {
		float2(0.0, 0.0),
		float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
	};
	for (int i = 0; i < 5; i++) {
		float3 c = getSource(input.uv + offsets[i] * _PostFXSource_TexelSize.xy).rgb;
		c = ApplyBloomThreshould(c);
		float weight = 1.0f / (Luminance(c) + 1.0f);
		color += c * weight;
		weightSum += weight;
	}
	color /= weightSum;
	return float4(color, 1.0f);
}

float4 _ColorAdjustments;
float4 _ColorFilter;
float4 _WhiteBalance;
float4 _SplitToningShadow, _SplitToningHighlight;
float4 _ChannelMixerRed, _ChannelMixerGreen, _ChannelMixerBlue;
float4 _SMHShadow, _SMHMidtone, _SMHHighlight, _SMHRange;

float Luminance(float3 color, bool useACES) {
	return useACES ? AcesLuminance(color) : Luminance(color);
}

float3 ColorGradePostExposure(float3 color) {
	return color * _ColorAdjustments.x;	//���ع������������
}

float3 ColorWhiteBalanceExposure(float3 color) {
	color = LinearToLMS(color);
	color *= _WhiteBalance.rgb;	//�任��ůɫ��
	return LMSToLinear(color);
}

float3 ColorGradingContrast(float3 color, bool useACES) {
	color = useACES ? ACES_to_ACEScc(unity_to_ACES(color)) : LinearToLogC(color);
	//�Աȶȣ����ǽ���ɫ��ȥ�Ҷȣ���ô���Ļ����0�����Ļ�С��0��������y��������1�����ϻҶȺ�ʱ�����Ӿ���ɫ�����ȣ����ĸ��������ĸ���
	color = (color - ACEScc_MIDGRAY) * _ColorAdjustments.y + ACEScc_MIDGRAY;
	return useACES ? ACES_to_ACEScg(ACEScc_to_ACES(color)) : LogCToLinear(color);
}

//����ɫ����ʹ�ø߹����Ӱ�в�ͬ�ı仯
float3 ColorGradeSplitToning(float3 color, bool useACES) {
	color = PositivePow(color, 1.0 / 2.2);
	float t = saturate(Luminance(saturate(color), useACES) + _SplitToningShadow.w);
	float3 shadow = lerp(0.5f, _SplitToningShadow.rgb, 1.0f - t);
	float3 highLight = lerp(0.5f, _SplitToningHighlight.rgb, t);
	color = SoftLight(color, shadow);
	color = SoftLight(color, highLight);
	return PositivePow(color, 2.2);
}

float3 ColorGradingChannelMixer(float3 color) {
	return mul(float3x3(_ChannelMixerRed.rgb, _ChannelMixerGreen.rgb, _ChannelMixerBlue.rgb), color);
}

//������������Ȩ�أ�ʹ�ð��ĵط��Զ���İ�����ɫȨ�ش����ĵط��Զ��������Ȩ�ش�
float3 ColorGradingShadowMidtonesHighlight(float3 color, bool useACES) {
	float luminance = Luminance(color, useACES);
	//smooth����Ϊx=clamp((x-a)/(b-a), 0, 1),return x^2(3-2x)
	float shadowWeight = 1.0f - smoothstep(_SMHRange.x, _SMHRange.y, luminance);
	float highlightWeight = smoothstep(_SMHRange.z, _SMHRange.w, luminance);
	float midtoneWeight = 1.0f - shadowWeight - highlightWeight;
	return color * _SMHShadow.rgb * shadowWeight + color * _SMHMidtone.rgb * midtoneWeight + color * _SMHHighlight.rgb * highlightWeight;
}

float3 ColorGradingHueShift(float3 color) {
	color = RgbToHsv(color);	//��rgb��Ϊhsv��hsv��x��������
	float hue = color.x + _ColorAdjustments.z;	//�޸�ɫ��
	color.x = RotateHue(hue, 0.0f, 1.0f);
	return HsvToRgb(color);
}

float3 ColorGradingSaturation(float3 color, bool useACES) {
	float luminance = Luminance(color, useACES);
	return (color - luminance) * _ColorAdjustments.w + luminance;	//���Ͷȣ���w��������1ʱ����ɫ��ȥ���ȳ�w�ټӻ����ȣ�ʹ�����ɫͨ����ø���С�ĸ�С
}

float3 ColorGrade(float3 color, bool useACES) {
	color = ColorGradePostExposure(color);
	color = ColorWhiteBalanceExposure(color);
	color = ColorGradingContrast(color, useACES);
	color *= _ColorFilter.rgb;	//ɫ���˾����Ǽ򵥵ĳ�����ɫ
	color = max(color, 0.0f);
	color = ColorGradeSplitToning(color, useACES);
	color = ColorGradingChannelMixer(color);
	color = max(color, 0.0f);
	color = ColorGradingShadowMidtonesHighlight(color, useACES);
	color = ColorGradingHueShift(color);
	color = ColorGradingSaturation(color, useACES);
	return max(useACES ? ACEScg_to_ACES(color) : color, 0.0f);
}

float4 _ColorGradingLUTParameters;
bool _ColorGradingLUTInLogC;

float3 getColorGradedLUT(float2 uv, bool useACES = false) {
	float3 color = GetLutStripValue(uv, _ColorGradingLUTParameters);
	return ColorGrade(_ColorGradingLUTInLogC ? LogCToLinear(color) : color, useACES);
}

float4 BloomToneMappingNonePassFragment(Varyings i) : SV_TARGET{
	float3 color = getColorGradedLUT(i.uv).rgb;
	return float4(color, 1.0f);
}

float4 BloomToneMappingACESPassFragment(Varyings i) : SV_TARGET{
	float3 color = getColorGradedLUT(i.uv, true).rgb;
	color = AcesTonemap(color);
	return float4(color, 1.0f);
}

float4 BloomToneMappingNeutralPassFragment(Varyings i) : SV_TARGET{
	float3 color = getColorGradedLUT(i.uv).rgb;
	color = NeutralTonemap(color);
	return float4(color, 1.0f);
}

float4 BloomToneMappingReinhardPassFragment(Varyings i) : SV_TARGET{
	float3 color = getColorGradedLUT(i.uv).rgb;
	color = color / (color + 1.0f);
	return float4(color, 1.0f);
}

float4 BloomToneMappingEPassFragment(Varyings i) : SV_TARGET{
	float3 color = getColorGradedLUT(i.uv).rgb;
	color = 1.0f - exp(-color);
	return float4(color, 1.0f);
}

float3 ApplyColorGradingLUT(float3 color) {
	//��һ��Ӧ�����н�HDRתΪLDR�Ĺ���
	return ApplyLut2D(
		TEXTURE2D_ARGS(_ColorGradingLUT, sampler_linear_clamp),
		saturate(_ColorGradingLUTInLogC ? LinearToLogC(color) : color),
		_ColorGradingLUTParameters.xyz
	);
}

float4 ApplyColorGradingPassFragment(Varyings i) : SV_TARGET{
	float4 color = getSource(i.uv);
	color.rgb = ApplyColorGradingLUT(color.rgb);
	return color;
}

float4 ApplyColorGradingWithLumaPassFragment(Varyings input) : SV_TARGET{
	float4 color = getSource(input.uv);
	color.rgb = ApplyColorGradingLUT(color.rgb);
	color.a = sqrt(Luminance(color.rgb));
	return color;
}

bool _CopyBicubic;

float4 FinalPassFragmentRescale(Varyings i) : SV_TARGET{
	if (_CopyBicubic) {
		return getSourceBicubic(i.uv);
	}
	else {
		return getSource(i.uv);
	}
	
}

#endif