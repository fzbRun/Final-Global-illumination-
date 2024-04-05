
#ifndef CUSTOM_FXAA_PASS_INCLUDED
#define CUSTOM_FXAA_PASS_INCLUDED

#if defined(FXAA_QUALITY_LOW)
	#define EXTRA_EDGE_STEPS 3
	#define EDGE_STEP_SIZES 1.5, 2.0, 2.0
	#define LAST_EDGE_STEP_GUESS 8.0
#elif defined(FXAA_QUALITY_MEDIUM)
	#define EXTRA_EDGE_STEPS 8
	#define EDGE_STEP_SIZES 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0
	#define LAST_EDGE_STEP_GUESS 8.0
#else
	#define EXTRA_EDGE_STEPS 10
	#define EDGE_STEP_SIZES 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0
	#define LAST_EDGE_STEP_GUESS 8.0
#endif

static const float edgeStepSizes[EXTRA_EDGE_STEPS] = { EDGE_STEP_SIZES };

float4 _FXAAConfig;

struct LumaNeighborhood {
	float m, n, e, s, w, ne, se, sw, nw;
	float highest, lowest, range;
};

struct FXAAEdge {
	bool isHorizontal;	//�߽��Ƿ���ˮƽ
	float pixelStep;	//���ķ���
	float lumaGradient, otherLuma;	//�߽��ϲ����������ص�����Ȳ�ֵ��Ҳ�������ұ߽�ʱ����ֵ	�����������
};

float GetLuma(float2 uv, float uOffset = 0.0, float vOffset = 0.0) {

	uv += float2(uOffset, vOffset) * _PostFXSource_TexelSize.xy;

#if defined(FXAA_ALPHA_CONTAINS_LUMA)
	return getSource(uv).a;
#else
	return getSource(uv).g;
#endif
}

LumaNeighborhood GetLumaNeighborhood(float2 uv) {
	LumaNeighborhood luma;
	luma.m = GetLuma(uv);
	luma.n = GetLuma(uv, 0.0, 1.0);
	luma.e = GetLuma(uv, 1.0, 0.0);
	luma.s = GetLuma(uv, 0.0, -1.0);
	luma.w = GetLuma(uv, -1.0, 0.0);
	luma.ne = GetLuma(uv, 1.0, 1.0);
	luma.se = GetLuma(uv, 1.0, -1.0);
	luma.sw = GetLuma(uv, -1.0, -1.0);
	luma.nw = GetLuma(uv, -1.0, 1.0);

	luma.highest = max(max(max(max(luma.m, luma.n), luma.e), luma.s), luma.w);
	luma.lowest = min(min(min(min(luma.m, luma.n), luma.e), luma.s), luma.w);
	luma.range = luma.highest - luma.lowest;
	return luma;
}

bool CanSkipFXAA(LumaNeighborhood luma) {
	bool skip;
	//ͨ��_FXAAConfig.y * luma.highest˵��Խ���ĵط���ֵ����
	skip = luma.range < max(_FXAAConfig.x, _FXAAConfig.y * luma.highest);
	return skip;
}

float getSubpixelBlendFactor(LumaNeighborhood luma) {
	float filter = 2.0f * (luma.n + luma.e + luma.s + luma.w);
	filter += luma.ne + luma.se + luma.sw + luma.nw;
	filter *= 1.0f / 12;
	filter = abs(filter - luma.m);	//λ�ڱ߽�ʱ�ϴ�,�ⲿԽ��Խ���ڲ�Խ��ԽС��������Ƶ��Ϣ
	filter = saturate(filter / luma.range);	//��һ��
	filter = smoothstep(0, 1, filter);
	return filter * filter * _FXAAConfig.z;	//����ģʽ��˫���Բ�ֵ
}

//��ֻ�����ص��4�����������������ͨ��4��������Խǲ�����Ƚ�
bool isHorizontalEdge(LumaNeighborhood luma) {
	float horizontal = 2.0f * abs(luma.n + luma.s - 2.0f * luma.m) + abs(luma.ne + luma.se - 2.0f * luma.e) + abs(luma.nw + luma.sw - 2.0f * luma.w);
	float vertical = 2.0f * abs(luma.e + luma.w - 2.0f * luma.m) + abs(luma.ne + luma.nw - 2.0f * luma.n) + abs(luma.se + luma.sw - 2.0f * luma.s);
	return horizontal >= vertical;
}

FXAAEdge GetFXAAEdge(LumaNeighborhood luma) {

	FXAAEdge edge;
	float lumaP, lumaN;

	edge.isHorizontal = isHorizontalEdge(luma);
	if (edge.isHorizontal) {
		edge.pixelStep = _PostFXSource_TexelSize.y;
		lumaP = luma.n;
		lumaN = luma.s;
	}
	else {
		edge.pixelStep = _PostFXSource_TexelSize.x;
		lumaP = luma.e;
		lumaN = luma.w;
	}

	float gradientP = abs(lumaP - luma.m);
	float gradientN = abs(lumaN - luma.m);

	if (gradientP < gradientN) {
		edge.pixelStep = -edge.pixelStep;
		edge.lumaGradient = gradientN;
		edge.otherLuma = lumaN;
	}
	else {
		edge.lumaGradient = gradientP;
		edge.otherLuma = lumaP;
	}

	return edge;
}

float GetEdgeBlendFactor(LumaNeighborhood luma, FXAAEdge edge, float2 uv) {

	float2 edgeUV = uv;
	float2 uvStep = 0.0f;

	if (edge.isHorizontal) {
		edgeUV.y += 0.5f * edge.pixelStep;
		uvStep.x = _PostFXSource_TexelSize.x;
	}
	else {
		edgeUV.x += 0.5f * edge.pixelStep;
		uvStep.y = _PostFXSource_TexelSize.y;
	}

	float edgeLuma = 0.5 * (luma.m + edge.otherLuma);	//���ص������ڵĲ������ƽ��ֵ
	float gradientThreshold = 0.25 * edge.lumaGradient;	//���ȵ���ֵ��Ϊ��ֵ��0.25

	//�������������˫���Բ�ֵ����������ȡ�м���������������ص�ƽ��ֵ
	float2 uvP = edgeUV + uvStep;
	float lumaDeltaP = GetLuma(uvP) - edgeLuma;	//�õ�������ƽ��ֵ�����ص�ƽ��ֵ�Ĳ�ֵ
	bool atEndP = abs(lumaDeltaP) >= gradientThreshold;
	UNITY_UNROLL
	for (int i = 0; i < EXTRA_EDGE_STEPS && !atEndP; i++) {
		uvP += uvStep * edgeStepSizes[i];
		lumaDeltaP = GetLuma(uvP) - edgeLuma;
		atEndP = abs(lumaDeltaP) >= gradientThreshold;
	}
	if (!atEndP) {
		uvP += uvStep * LAST_EDGE_STEP_GUESS;
	}

	float2 uvN = edgeUV - uvStep;
	float lumaDeltaN = GetLuma(uvN) - edgeLuma;
	bool atEndN = abs(lumaDeltaN) >= gradientThreshold;
	UNITY_UNROLL
	for (int i = 0; i < EXTRA_EDGE_STEPS && !atEndN; i++) {
		uvN -= uvStep * edgeStepSizes[i];
		lumaDeltaN = GetLuma(uvN) - edgeLuma;
		atEndN = abs(lumaDeltaN) >= gradientThreshold;
	}
	if (!atEndN) {
		uvN -= uvStep * LAST_EDGE_STEP_GUESS;
	}

	float distanceToEndP, distanceToEndN;
	if (edge.isHorizontal) {
		distanceToEndP = uvP.x - uv.x;	//�õ�����������ղ����������ص�֮�����
		distanceToEndN = uv.x - uvN.x;
	}
	else {
		distanceToEndP = uvP.y - uv.y;
		distanceToEndN = uv.y - uvN.y;
	}

	float distanceToNearestEnd;
	bool deltaSign;
	/*
	if (abs(GetLuma(uvP - edgeUV + uv) - luma.m) < abs(GetLuma(uvN - edgeUV + uv) - luma.m)) {
		distanceToNearestEnd = distanceToEndP;
		deltaSign = lumaDeltaP >= 0;
	}
	else {
		distanceToNearestEnd = distanceToEndN;
		deltaSign = lumaDeltaN >= 0;
	}
	*/
	
	if (distanceToEndP <= distanceToEndN) {	//�õ�������������С�ľ���
		distanceToNearestEnd = distanceToEndP;
		deltaSign = lumaDeltaP >= 0;	//�ж������������ղ�����������Ƿ�������ص�
	}
	else {
		distanceToNearestEnd = distanceToEndN;
		deltaSign = lumaDeltaN >= 0;
	}
	
	if (deltaSign == (luma.m - edgeLuma >= 0)) {	//�����ղ���������ص�������ʱ�����
		return 0.0;
	}
	else {
		return 0.5f - distanceToNearestEnd / (distanceToEndP + distanceToEndN);
	}

}

float4 FXAAPassFragment(Varyings input) : SV_TARGET{
	LumaNeighborhood luma = GetLumaNeighborhood(input.uv);

	if (CanSkipFXAA(luma)) {
		return getSource(input.uv);
	}

	FXAAEdge edge = GetFXAAEdge(luma);

	//float blendFactor = getSubpixelBlendFactor(luma);
	float blendFactor = max(getSubpixelBlendFactor(luma), GetEdgeBlendFactor(luma, edge, input.uv));
	//float blendFactor = GetEdgeBlendFactor(luma, edge, input.uv);
	float2 blendUV = input.uv;
	if (edge.isHorizontal) {
		blendUV.y += edge.pixelStep * blendFactor;
	}
	else {
		blendUV.x += edge.pixelStep * blendFactor;
	}

	return getSource(blendUV);
}

#endif
